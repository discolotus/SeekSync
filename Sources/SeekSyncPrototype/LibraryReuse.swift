import AudioToolbox
import CryptoKit
import Foundation

struct LibraryReuseConditionPolicy: Hashable {
    var arguments: [String]

    var fingerprint: String {
        let canonical = arguments.joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct PlaylistTrackSeed: Codable, Hashable, Identifiable {
    var position: Int
    var artist: String
    var title: String
    var album: String?
    var lengthSeconds: Int?

    var id: String {
        "\(position)\u{1F}\(artist.lowercased())\u{1F}\(title.lowercased())"
    }

    fileprivate var exactIndexKey: String {
        SockseekIndexEntry.key(
            artist: artist,
            album: album ?? "",
            title: title,
            length: lengthSeconds ?? -1
        )
    }

    fileprivate var metadataIndexKey: String {
        SockseekIndexEntry.metadataKey(artist: artist, album: album ?? "", title: title)
    }
}

enum PlaylistTrackDisposition: String, Codable, Hashable {
    case libraryReference
    case libraryBelowThreshold
    case downloadRequired
    case downloaded
    case unavailable
    case unknown
}

struct AudioFileQuality: Codable, Hashable {
    var format: String
    var bitrateKbps: Int?
    var sampleRateHz: Int?
    var bitDepth: Int?
    var durationSeconds: Double?

    var displayLabel: String {
        var parts = [format.uppercased()]
        if let bitrateKbps, bitrateKbps > 0 {
            parts.append("\(bitrateKbps) kbps")
        }
        if let sampleRateHz, sampleRateHz > 0 {
            let khz = Double(sampleRateHz) / 1_000
            let formatted = khz.rounded() == khz
                ? String(format: "%.0f kHz", khz)
                : String(format: "%.1f kHz", khz)
            parts.append(formatted)
        }
        if let bitDepth, bitDepth > 0 {
            parts.append("\(bitDepth)-bit")
        }
        return parts.joined(separator: " · ")
    }
}

struct PlaylistTrackRecord: Codable, Hashable, Identifiable {
    var seed: PlaylistTrackSeed
    var disposition: PlaylistTrackDisposition
    var localPath: String?
    var quality: AudioFileQuality?

    var id: String { seed.id }
}

enum PlaylistLibraryAnalysisBasis: String, Codable, Hashable {
    case preview
    case completedSync
}

struct PlaylistLibraryAnalysis: Codable, Hashable {
    var playlistID: String
    var playlistName: String
    var analyzedAt: Date
    var sourceLibraryPath: String
    var preferredFormat: String
    var minimumBitrateKbps: Int?
    var tracks: [PlaylistTrackRecord]
    var playlistSnapshotID: String? = nil
    var playlistTrackCount: Int? = nil
    var basis: PlaylistLibraryAnalysisBasis? = nil
    var conditionFingerprint: String? = nil

    var targetLabel: String {
        let format = preferredFormat.uppercased()
        guard let minimumBitrateKbps, minimumBitrateKbps > 0 else {
            return "\(format) preferred"
        }
        return "\(format) · at least \(minimumBitrateKbps) kbps"
    }

    var referenceCount: Int {
        tracks.lazy.filter { $0.disposition == .libraryReference }.count
    }

    var belowThresholdCount: Int {
        tracks.lazy.filter { $0.disposition == .libraryBelowThreshold }.count
    }

    var downloadRequiredCount: Int {
        tracks.lazy.filter { $0.disposition == .downloadRequired }.count
    }

    var downloadedCount: Int {
        tracks.lazy.filter { $0.disposition == .downloaded }.count
    }

    var unavailableCount: Int {
        tracks.lazy.filter { $0.disposition == .unavailable || $0.disposition == .unknown }.count
    }

    var basisLabel: String {
        switch basis {
        case .preview: return "Read-only preview"
        case .completedSync: return "Completed sync result"
        case nil: return "Saved inventory"
        }
    }

    func isCurrent(
        for settings: ClientSettings,
        playlist: Playlist? = nil,
        conditionFingerprint currentConditionFingerprint: String? = nil
    ) -> Bool {
        let targetIsCurrent = standardized(sourceLibraryPath) == standardized(settings.libraryDirectoryPath)
            && preferredFormat.caseInsensitiveCompare(settings.preferredFormatValue) == .orderedSame
            && minimumBitrateKbps == Int(settings.preferredMinBitrateConfigValue)
        guard targetIsCurrent else { return false }
        if let currentConditionFingerprint,
           conditionFingerprint != currentConditionFingerprint {
            return false
        }
        guard let playlist else { return true }
        if let snapshotID = playlist.snapshotID {
            return playlistSnapshotID == snapshotID
        }
        if let playlistTrackCount, playlist.trackCount > 0 {
            return playlistTrackCount == playlist.trackCount
        }
        return true
    }

    private func standardized(_ path: String) -> String {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL.path
    }
}

enum LibraryReuseAnalysisError: LocalizedError {
    case missingLibrary
    case playlistExtractionFailed(String)
    case noPlaylistTracks
    case previewPassIncomplete(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .missingLibrary:
            return "The existing music library folder is unavailable or unreadable."
        case .playlistExtractionFailed(let detail):
            return "Could not read the playlist without downloading: \(detail)"
        case .noPlaylistTracks:
            return "Sockseek did not return any song tracks for this playlist."
        case .previewPassIncomplete(let pass, let status, let detail):
            return "The \(pass) library preview did not complete reliably (Sockseek status \(status); \(detail)). No preview was saved."
        }
    }
}

struct SockseekJobsFullParser {
    func parse(_ output: String) -> [PlaylistTrackSeed] {
        struct Draft {
            var artist = ""
            var title = ""
            var album: String?
            var lengthSeconds: Int?
        }

        var result: [PlaylistTrackSeed] = []
        var draft: Draft?

        func value(in line: String, after field: String) -> String? {
            guard line.hasPrefix(field) else { return nil }
            return String(line.dropFirst(field.count)).trimmingCharacters(in: .whitespaces)
        }

        func append(_ draft: Draft?, to result: inout [PlaylistTrackSeed]) {
            guard let draft,
                  !draft.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            result.append(
                PlaylistTrackSeed(
                    position: result.count + 1,
                    artist: draft.artist,
                    title: draft.title,
                    album: draft.album?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
                    lengthSeconds: draft.lengthSeconds
                )
            )
        }

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "Song:" {
                append(draft, to: &result)
                draft = Draft()
                continue
            }
            guard draft != nil else { continue }
            if line.hasSuffix(":"), !line.hasPrefix("Artist:"), !line.hasPrefix("Title:"),
               !line.hasPrefix("Album:"), !line.hasPrefix("Length:"), !line.hasPrefix("URL/ID:") {
                append(draft, to: &result)
                draft = nil
                continue
            }
            if let artist = value(in: line, after: "Artist:") {
                draft?.artist = artist
            } else if let title = value(in: line, after: "Title:") {
                draft?.title = title
            } else if let album = value(in: line, after: "Album:") {
                draft?.album = album
            } else if let length = value(in: line, after: "Length:") {
                draft?.lengthSeconds = Int(length.trimmingCharacters(in: CharacterSet(charactersIn: "sS")))
            }
        }
        append(draft, to: &result)
        return result
    }
}

struct SockseekIndexEntry: Hashable {
    var path: String?
    var artist: String
    var album: String
    var title: String
    var lengthSeconds: Int
    var state: Int
    var failureReason: Int

    var exactKey: String {
        Self.key(artist: artist, album: album, title: title, length: lengthSeconds)
    }

    var metadataKey: String {
        Self.metadataKey(artist: artist, album: album, title: title)
    }

    var isExisting: Bool { state == 3 && path?.isEmpty == false }
    var isDownloaded: Bool { state == 1 && path?.isEmpty == false }
    var isAvailable: Bool { (state == 1 || state == 3) && path?.isEmpty == false }

    fileprivate static func key(artist: String, album: String, title: String, length: Int) -> String {
        "\(normalized(artist))\u{1F}\(normalized(album))\u{1F}\(normalized(title))\u{1F}\(length)"
    }

    fileprivate static func metadataKey(artist: String, album: String, title: String) -> String {
        "\(normalized(artist))\u{1F}\(normalized(album))\u{1F}\(normalized(title))"
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct SockseekIndexParser {
    func parse(url: URL) throws -> [SockseekIndexEntry] {
        let data = try Data(contentsOf: url)
        let rows = CSVCodec.rows(in: String(decoding: data, as: UTF8.self))
        guard rows.count > 1 else { return [] }
        let parent = url.deletingLastPathComponent()
        return rows.dropFirst().compactMap { fields in
            guard fields.count >= 8,
                  !fields.dropFirst().allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                return nil
            }
            let rawPath = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedPath: String?
            if rawPath.isEmpty {
                resolvedPath = nil
            } else if rawPath.hasPrefix("./") {
                resolvedPath = parent.appendingPathComponent(String(rawPath.dropFirst(2))).standardizedFileURL.path
            } else {
                resolvedPath = URL(fileURLWithPath: rawPath).standardizedFileURL.path
            }
            return SockseekIndexEntry(
                path: resolvedPath,
                artist: fields[1],
                album: fields[2],
                title: fields[3],
                lengthSeconds: Int(fields[4]) ?? -1,
                state: Int(fields[6]) ?? 0,
                failureReason: Int(fields[7]) ?? 0
            )
        }
    }
}

private enum CSVCodec {
    static func rows(in input: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = input.startIndex

        func finishField() {
            row.append(field)
            field = ""
        }

        func finishRow() {
            finishField()
            if !row.allSatisfy({ $0.isEmpty }) { rows.append(row) }
            row = []
        }

        while index < input.endIndex {
            let character = input[index]
            let next = input.index(after: index)
            if character == "\"" {
                if quoted, next < input.endIndex, input[next] == "\"" {
                    field.append("\"")
                    index = input.index(after: next)
                    continue
                }
                quoted.toggle()
            } else if character == ",", !quoted {
                finishField()
            } else if character == "\n", !quoted {
                finishRow()
            } else if character != "\r" || quoted {
                field.append(character)
            }
            index = next
        }
        if !field.isEmpty || !row.isEmpty { finishRow() }
        return rows
    }

    static func line(_ fields: [String]) -> String {
        fields.map { value in
            if value.contains(",") || value.contains("\"") || value.contains("\n") {
                return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return value
        }.joined(separator: ",")
    }
}

struct AudioFileQualityProbe {
    func inspect(paths: Set<String>) async -> [String: AudioFileQuality] {
        await Task.detached(priority: .utility) {
            var result: [String: AudioFileQuality] = [:]
            for path in paths.sorted() {
                if Task.isCancelled { break }
                result[path] = Self.inspect(path: path)
            }
            return result
        }.value
    }

    private static func inspect(path: String) -> AudioFileQuality {
        let url = URL(fileURLWithPath: path)
        let fallbackFormat = url.pathExtension.isEmpty ? "audio" : url.pathExtension.lowercased()
        var fileID: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &fileID) == noErr,
              let fileID else {
            return AudioFileQuality(
                format: fallbackFormat,
                bitrateKbps: nil,
                sampleRateHz: nil,
                bitDepth: nil,
                durationSeconds: nil
            )
        }
        defer { AudioFileClose(fileID) }

        var description = AudioStreamBasicDescription()
        var descriptionSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let hasDescription = AudioFileGetProperty(
            fileID,
            kAudioFilePropertyDataFormat,
            &descriptionSize,
            &description
        ) == noErr

        var bitrate: UInt32 = 0
        var bitrateSize = UInt32(MemoryLayout<UInt32>.size)
        let hasBitrate = AudioFileGetProperty(fileID, kAudioFilePropertyBitRate, &bitrateSize, &bitrate) == noErr

        var sourceBitDepth: UInt32 = 0
        var depthSize = UInt32(MemoryLayout<UInt32>.size)
        let hasDepth = AudioFileGetProperty(
            fileID,
            kAudioFilePropertySourceBitDepth,
            &depthSize,
            &sourceBitDepth
        ) == noErr

        var duration: Float64 = 0
        var durationSize = UInt32(MemoryLayout<Float64>.size)
        let hasDuration = AudioFileGetProperty(
            fileID,
            kAudioFilePropertyEstimatedDuration,
            &durationSize,
            &duration
        ) == noErr

        let codec = hasDescription ? codecLabel(description.mFormatID) : nil
        let format = codec == "AAC" || codec == "ALAC" ? codec!.lowercased() : (codec?.lowercased() ?? fallbackFormat)
        let streamDepth = hasDescription && description.mBitsPerChannel > 0 ? Int(description.mBitsPerChannel) : nil
        return AudioFileQuality(
            format: format,
            bitrateKbps: hasBitrate && bitrate > 0 ? Int((Double(bitrate) / 1_000).rounded()) : nil,
            sampleRateHz: hasDescription && description.mSampleRate > 0 ? Int(description.mSampleRate.rounded()) : nil,
            bitDepth: hasDepth && sourceBitDepth > 0 ? Int(sourceBitDepth) : streamDepth,
            durationSeconds: hasDuration && duration > 0 ? duration : nil
        )
    }

    private static func codecLabel(_ value: AudioFormatID) -> String? {
        switch value {
        case kAudioFormatMPEGLayer3: return "MP3"
        case kAudioFormatFLAC: return "FLAC"
        case kAudioFormatAppleLossless: return "ALAC"
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2: return "AAC"
        case kAudioFormatLinearPCM: return "WAV"
        default: return nil
        }
    }
}

struct LibraryReuseAnalyzer {
    private let runner = SockseekProcessRunner()
    private let indexParser = SockseekIndexParser()
    private let jobsParser = SockseekJobsFullParser()
    private let qualityProbe = AudioFileQualityProbe()
    private let fileManager = FileManager.default

    func analyze(
        playlist: Playlist,
        settings: ClientSettings,
        conditionPolicy: LibraryReuseConditionPolicy = LibraryReuseConditionPolicy(arguments: []),
        onStage: ((String) async -> Void)? = nil
    ) async throws -> PlaylistLibraryAnalysis {
        let libraryPath = NSString(string: settings.libraryDirectoryPath).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: libraryPath, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fileManager.isReadableFile(atPath: libraryPath) else {
            throw LibraryReuseAnalysisError.missingLibrary
        }

        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SeekSync-LibraryPreview-\(UUID().uuidString)", isDirectory: true)
        let mock = root.appendingPathComponent("empty-mock", isDirectory: true)
        let gatedOutput = root.appendingPathComponent("quality-gated-output", isDirectory: true)
        let ungatedOutput = root.appendingPathComponent("all-matches-output", isDirectory: true)
        try fileManager.createDirectory(at: mock, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: gatedOutput, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: ungatedOutput, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        defer { try? fileManager.removeItem(at: root) }

        await onStage?("Reading playlist metadata without contacting Soulseek…")
        let extraction = try await runner.run(metadataCommand(for: playlist, settings: settings))
        let seeds = jobsParser.parse(extraction.output)
        guard !seeds.isEmpty else {
            let detail = extraction.output
                .split(whereSeparator: \.isNewline)
                .suffix(3)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if extraction.exitCode != 0, !detail.isEmpty {
                throw LibraryReuseAnalysisError.playlistExtractionFailed(detail)
            }
            throw LibraryReuseAnalysisError.noPlaylistTracks
        }

        let input = root.appendingPathComponent("playlist.csv")
        try writePlaylistCSV(seeds, to: input)
        let gatedIndex = root.appendingPathComponent("quality-gated-index.csv")
        let ungatedIndex = root.appendingPathComponent("all-matches-index.csv")
        let stableIndexPath = SockseekCommandBuilder().indexPath(
            for: playlist,
            outputDirectory: settings.outputDirectory
        )
        let stableEntries: [SockseekIndexEntry]
        if fileManager.fileExists(atPath: standardized(stableIndexPath)) {
            stableEntries = ((try? indexParser.parse(url: URL(fileURLWithPath: standardized(stableIndexPath)))) ?? [])
                .filter { entry in
                    !entry.isAvailable || entry.path.map { fileManager.fileExists(atPath: $0) } == true
                }
        } else {
            stableEntries = []
        }
        if !stableEntries.isEmpty {
            try writeIndexSnapshot(stableEntries, to: gatedIndex)
            try writeIndexSnapshot(stableEntries, to: ungatedIndex)
        }

        await onStage?("Checking which local tracks meet \(settings.preferredFormatLabel)…")
        let gatedResult = try await runner.run(
            previewCommand(
                input: input,
                output: gatedOutput,
                index: gatedIndex,
                mock: mock,
                libraryPath: libraryPath,
                settings: settings,
                conditionPolicy: conditionPolicy,
                checksPreferredQuality: true
            )
        )
        let gated = try validatePreviewPass(
            gatedResult,
            index: gatedIndex,
            seeds: seeds,
            pass: "quality-gated"
        )

        await onStage?("Separating local matches that miss the reuse conditions from missing tracks…")
        let ungatedResult = try await runner.run(
            previewCommand(
                input: input,
                output: ungatedOutput,
                index: ungatedIndex,
                mock: mock,
                libraryPath: libraryPath,
                settings: settings,
                conditionPolicy: conditionPolicy,
                checksPreferredQuality: false
            )
        )
        let ungated = try validatePreviewPass(
            ungatedResult,
            index: ungatedIndex,
            seeds: seeds,
            pass: "all-matches"
        )
        let gatedEntries = EntryLookup(entries: gated).entries(for: seeds)
        let ungatedEntries = EntryLookup(entries: ungated).entries(for: seeds)
        let selectedPaths = Set(
            seeds.indices.flatMap { index in
                [gatedEntries[index]?.path, ungatedEntries[index]?.path]
                    .compactMap { $0 }
                    .filter { fileManager.fileExists(atPath: $0) }
            }
        )
        await onStage?("Reading technical quality for matched local files…")
        let qualities = await qualityProbe.inspect(paths: selectedPaths)

        let tracks = seeds.enumerated().map { offset, seed -> PlaylistTrackRecord in
            if let entry = gatedEntries[offset], entry.isAvailable, let path = entry.path,
               fileManager.fileExists(atPath: path) {
                let disposition: PlaylistTrackDisposition = contains(path, in: settings.outputDirectory)
                    ? .downloaded
                    : .libraryReference
                return PlaylistTrackRecord(
                    seed: seed,
                    disposition: disposition,
                    localPath: path,
                    quality: qualities[path]
                )
            }
            if let entry = ungatedEntries[offset], entry.isAvailable, let path = entry.path,
               fileManager.fileExists(atPath: path) {
                return PlaylistTrackRecord(
                    seed: seed,
                    disposition: .libraryBelowThreshold,
                    localPath: path,
                    quality: qualities[path]
                )
            }
            return PlaylistTrackRecord(
                seed: seed,
                disposition: .downloadRequired,
                localPath: nil,
                quality: nil
            )
        }

        return PlaylistLibraryAnalysis(
            playlistID: playlist.id,
            playlistName: playlist.name,
            analyzedAt: Date(),
            sourceLibraryPath: libraryPath,
            preferredFormat: settings.preferredFormatValue,
            minimumBitrateKbps: Int(settings.preferredMinBitrateConfigValue),
            tracks: tracks,
            playlistSnapshotID: playlist.snapshotID,
            playlistTrackCount: seeds.count,
            basis: .preview,
            conditionFingerprint: conditionPolicy.fingerprint
        )
    }

    /// Rebuilds the saved inventory from Sockseek's stable index after a real run.
    /// Unlike the preflight analysis, this records what actually happened: an
    /// external reference, a file in SeekSync's output folder, or an unresolved
    /// track. A below-target local match is retained when its replacement could
    /// not be downloaded so the quality warning remains visible.
    func completedAnalysis(
        playlist: Playlist,
        seeds progressSeeds: [PlaylistTrackSeed],
        previousAnalysis: PlaylistLibraryAnalysis?,
        command: SLDLCommand,
        conditionPolicy: LibraryReuseConditionPolicy = LibraryReuseConditionPolicy(arguments: [])
    ) async throws -> PlaylistLibraryAnalysis? {
        guard let indexPath = command.value(after: "--index-path"),
              let outputPath = command.value(after: "--output-dir") else {
            return nil
        }
        guard let libraryPath = command.value(after: "--skip-music-dir")
            ?? previousAnalysis?.sourceLibraryPath,
            !libraryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let indexURL = URL(fileURLWithPath: standardized(indexPath))
        guard fileManager.fileExists(atPath: indexURL.path) else { return nil }
        let entries = try indexParser.parse(url: indexURL)
        guard !entries.isEmpty else { return nil }

        let preferredFormat = command.value(after: "--pref-format")
            ?? previousAnalysis?.preferredFormat
            ?? "audio"
        let minimumBitrate = command.value(after: "--pref-min-bitrate").flatMap(Int.init)
            ?? previousAnalysis?.minimumBitrateKbps
        let currentLibraryPath = standardized(libraryPath)
        let reusablePrevious = previousAnalysis.flatMap { analysis -> PlaylistLibraryAnalysis? in
            guard standardized(analysis.sourceLibraryPath) == currentLibraryPath,
                  analysis.preferredFormat.caseInsensitiveCompare(preferredFormat) == .orderedSame,
                  analysis.minimumBitrateKbps == minimumBitrate else { return nil }
            guard analysis.conditionFingerprint == conditionPolicy.fingerprint
                    || (analysis.conditionFingerprint == nil && conditionPolicy.arguments.isEmpty) else {
                return nil
            }
            return analysis
        }

        let seeds: [PlaylistTrackSeed]
        if !progressSeeds.isEmpty {
            seeds = progressSeeds
        } else if let reusablePrevious, !reusablePrevious.tracks.isEmpty {
            seeds = reusablePrevious.tracks.map(\.seed)
        } else {
            seeds = entries.enumerated().map { offset, entry in
                PlaylistTrackSeed(
                    position: offset + 1,
                    artist: entry.artist,
                    title: entry.title,
                    album: entry.album.nilIfBlank,
                    lengthSeconds: entry.lengthSeconds >= 0 ? entry.lengthSeconds : nil
                )
            }
        }

        let matchedEntries = EntryLookup(entries: entries).entries(for: seeds)
        let paths = Set(matchedEntries.compactMap { $0?.path })
        let qualities = await qualityProbe.inspect(paths: paths)
        let previousRecords = PreviousRecordLookup(records: reusablePrevious?.tracks ?? [])

        let tracks = zip(seeds, matchedEntries).map { seed, entry -> PlaylistTrackRecord in
            let previous = previousRecords.record(for: seed).flatMap { record -> PlaylistTrackRecord? in
                guard let path = record.localPath,
                      fileManager.fileExists(atPath: path),
                      contains(path, in: currentLibraryPath) || contains(path, in: outputPath) else { return nil }
                return record
            }
            guard let entry else {
                return unresolvedRecord(seed: seed, previous: previous, disposition: .unknown)
            }

            if let path = entry.path, fileManager.fileExists(atPath: path) {
                if entry.state == 1 {
                    return PlaylistTrackRecord(
                        seed: seed,
                        disposition: .downloaded,
                        localPath: path,
                        quality: qualities[path]
                    )
                }
                if entry.state == 3 {
                    let disposition: PlaylistTrackDisposition = contains(path, in: outputPath)
                        ? .downloaded
                        : .libraryReference
                    return PlaylistTrackRecord(
                        seed: seed,
                        disposition: disposition,
                        localPath: path,
                        quality: qualities[path]
                    )
                }
            }

            if entry.state == 2 || entry.state == 4 {
                return unresolvedRecord(seed: seed, previous: previous, disposition: .unavailable)
            }
            return unresolvedRecord(seed: seed, previous: previous, disposition: .unknown)
        }

        return PlaylistLibraryAnalysis(
            playlistID: playlist.id,
            playlistName: playlist.name,
            analyzedAt: Date(),
            sourceLibraryPath: currentLibraryPath,
            preferredFormat: preferredFormat,
            minimumBitrateKbps: minimumBitrate,
            tracks: tracks,
            playlistSnapshotID: playlist.snapshotID,
            playlistTrackCount: seeds.count,
            basis: .completedSync,
            conditionFingerprint: conditionPolicy.fingerprint
        )
    }

    private func unresolvedRecord(
        seed: PlaylistTrackSeed,
        previous: PlaylistTrackRecord?,
        disposition: PlaylistTrackDisposition
    ) -> PlaylistTrackRecord {
        if let previous, previous.disposition == .libraryBelowThreshold {
            return PlaylistTrackRecord(
                seed: seed,
                disposition: .libraryBelowThreshold,
                localPath: previous.localPath,
                quality: previous.quality
            )
        }
        return PlaylistTrackRecord(
            seed: seed,
            disposition: disposition,
            localPath: nil,
            quality: nil
        )
    }

    private func contains(_ candidate: String, in root: String) -> Bool {
        let candidatePath = standardized(candidate)
        let rootPath = standardized(root)
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private func standardized(_ path: String) -> String {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    private func validatePreviewPass(
        _ result: ProcessResult,
        index: URL,
        seeds: [PlaylistTrackSeed],
        pass: String
    ) throws -> [SockseekIndexEntry] {
        var progress = SockseekProgressTracker()
        progress.consume(result.output)
        let processedSeeds = progress.playlistTracks
        let processedKeys = processedSeeds.map(Self.trackKey).sorted()
        let expectedKeys = seeds.map(Self.trackKey).sorted()
        let processedExpectedPlaylist = processedSeeds.count == seeds.count
            && processedKeys == expectedKeys

        let counts = progress.counts
        let completedExpectedPlaylist = progress.snapshot.totalTracks == seeds.count
            && progress.snapshot.completedTracks == seeds.count
            && counts.added == 0
            && counts.upgraded == 0
            && counts.needsReview == 0
            && counts.alreadyBest + counts.unavailable == seeds.count
        let expectedExitCode: Int32 = counts.unavailable == 0 ? 0 : 1
        let expectedFailures = progress.failures.count == counts.unavailable
            && progress.failures.allSatisfy { failure in
                Self.normalized(failure.terminalOutcome ?? "") == "failed"
                    && Self.normalized(failure.failureReason ?? "") == "nosearchresults"
            }

        guard processedExpectedPlaylist,
              completedExpectedPlaylist,
              result.exitCode == expectedExitCode,
              expectedFailures,
              fileManager.fileExists(atPath: index.path) else {
            let failureSummary = progress.failures.map { failure in
                (failure.terminalOutcome ?? "nil") + "/" + (failure.failureReason ?? "nil")
            }.joined(separator: "|")
            let detail = [
                "tracks \(processedSeeds.count)/\(seeds.count)",
                "terminal \(progress.snapshot.completedTracks)/\(progress.snapshot.totalTracks)",
                "existing \(counts.alreadyBest)",
                "unavailable \(counts.unavailable)",
                "checks metadata=\(processedExpectedPlaylist) terminal=\(completedExpectedPlaylist) status=\(result.exitCode == expectedExitCode) failures=\(expectedFailures)",
                "failures \(progress.failures.count) \(failureSummary)"
            ].joined(separator: ", ")
            throw LibraryReuseAnalysisError.previewPassIncomplete(pass, result.exitCode, detail)
        }

        let entries = try indexParser.parse(url: index)
        let matchedEntries = EntryLookup(entries: entries).entries(for: seeds)
        let resolvedEntries = matchedEntries.compactMap { $0 }
        let availableCount = resolvedEntries.lazy.filter(\.isAvailable).count
        guard resolvedEntries.count == seeds.count,
              availableCount == counts.alreadyBest,
              resolvedEntries.count - availableCount == counts.unavailable else {
            let detail = "index rows \(resolvedEntries.count)/\(seeds.count), available \(availableCount)/\(counts.alreadyBest)"
            throw LibraryReuseAnalysisError.previewPassIncomplete(pass, result.exitCode, detail)
        }
        return entries
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func trackKey(_ seed: PlaylistTrackSeed) -> String {
        normalized(seed.artist) + "\u{1F}" + normalized(seed.title)
    }

    private func metadataCommand(for playlist: Playlist, settings: ClientSettings) -> SLDLCommand {
        var arguments = [playlist.spotifyURL]
        if !settings.configPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += ["--config", settings.configPath]
        }
        if !settings.profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += ["--profile", settings.profileName]
        }
        arguments += [
            "--print", "jobs-full",
            "--no-progress",
            "--no-listen",
            "--no-write-index",
            "--write-playlist", "false",
            "--remove-from-source", "false",
            "--yt-dlp", "false"
        ]
        return SLDLCommand(
            executable: NSString(string: settings.binaryPath).expandingTildeInPath,
            arguments: arguments
        )
    }

    private func previewCommand(
        input: URL,
        output: URL,
        index: URL,
        mock: URL,
        libraryPath: String,
        settings: ClientSettings,
        conditionPolicy: LibraryReuseConditionPolicy,
        checksPreferredQuality: Bool
    ) -> SLDLCommand {
        var arguments = [
                input.path,
                "--no-config",
                "--output-dir", output.path,
                "--index-path", index.path,
                "--mock-files-dir", mock.path,
                "--mock-files-no-read-tags",
                "--skip-existing", "true",
                "--skip-mode-output-dir", "index",
                "--skip-music-dir", libraryPath,
                "--skip-mode-music-dir", "tag",
            ]
        arguments += conditionPolicy.arguments
        arguments += [
                "--skip-check-pref-cond", checksPreferredQuality ? "true" : "false",
                "--skip-not-found", "false",
                "--pref-format", settings.preferredFormatValue,
                "--pref-min-bitrate", settings.preferredMinBitrateConfigValue,
                "--progress-json",
                "--no-progress",
                "--write-playlist", "false",
                "--remove-from-source", "false",
                "--yt-dlp", "false",
                "--no-listen",
                "--concurrent-jobs", "1"
            ]
        if !checksPreferredQuality {
            arguments += ["--skip-check-cond", "false"]
        }
        return SLDLCommand(
            executable: NSString(string: settings.binaryPath).expandingTildeInPath,
            arguments: arguments
        )
    }

    private func writePlaylistCSV(_ seeds: [PlaylistTrackSeed], to url: URL) throws {
        var lines = [CSVCodec.line(["Artist", "Album", "Title", "Length"])]
        lines += seeds.map { seed in
            CSVCodec.line([
                seed.artist,
                seed.album ?? "",
                seed.title,
                String(seed.lengthSeconds ?? -1)
            ])
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func writeIndexSnapshot(_ entries: [SockseekIndexEntry], to url: URL) throws {
        var lines = [CSVCodec.line([
            "filepath", "artist", "album", "title", "length", "tracktype", "state", "failurereason"
        ])]
        lines += entries.map { entry in
            CSVCodec.line([
                entry.path ?? "",
                entry.artist,
                entry.album,
                entry.title,
                String(entry.lengthSeconds),
                "0",
                String(entry.state),
                String(entry.failureReason)
            ])
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

private struct EntryLookup {
    private let entries: [SockseekIndexEntry]
    private let exact: [String: [Int]]
    private let metadata: [String: [Int]]

    init(entries: [SockseekIndexEntry]) {
        self.entries = entries
        self.exact = entries.enumerated().reduce(into: [:]) { result, item in
            result[item.element.exactKey, default: []].append(item.offset)
        }
        self.metadata = entries.enumerated().reduce(into: [:]) { result, item in
            result[item.element.metadataKey, default: []].append(item.offset)
        }
    }

    func entry(for seed: PlaylistTrackSeed) -> SockseekIndexEntry? {
        let index = ((exact[seed.exactIndexKey] ?? []) + (metadata[seed.metadataIndexKey] ?? [])).max()
        return index.map { entries[$0] }
    }

    func entries(for seeds: [PlaylistTrackSeed]) -> [SockseekIndexEntry?] {
        var consumed: Set<Int> = []
        return seeds.map { seed in
            let candidates = Set((exact[seed.exactIndexKey] ?? []) + (metadata[seed.metadataIndexKey] ?? []))
                .sorted(by: >)
            guard let index = candidates.first(where: { !consumed.contains($0) }) else { return nil }
            consumed.insert(index)
            return entries[index]
        }
    }
}

private struct PreviousRecordLookup {
    private let records: [PlaylistTrackRecord]

    init(records: [PlaylistTrackRecord]) {
        self.records = records
    }

    func record(for seed: PlaylistTrackSeed) -> PlaylistTrackRecord? {
        records.first { $0.seed.id == seed.id }
            ?? records.first { $0.seed.exactIndexKey == seed.exactIndexKey }
            ?? records.first { $0.seed.metadataIndexKey == seed.metadataIndexKey }
    }
}

private extension SLDLCommand {
    func value(after option: String) -> String? {
        guard let index = arguments.lastIndex(of: option) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }
}

private extension String {
    var nilIfBlank: String? { isEmpty ? nil : self }
}
