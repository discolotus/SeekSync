import CryptoKit
import Foundation

enum ConfigStoreError: LocalizedError {
    case missing(URL)
    case externallyModified
    case unreadable(String)
    case existingFileWasNotLoaded

    var errorDescription: String? {
        switch self {
        case .missing(let url):
            return "No Sockseek config exists at \(url.path)."
        case .externallyModified:
            return "The config changed outside SeekSync. Reload it before saving so nothing is overwritten."
        case .unreadable(let message):
            return message
        case .existingFileWasNotLoaded:
            return "SeekSync will not overwrite an existing config that it could not load. Fix the file or choose a new path."
        }
    }
}

struct ConfigRevision: Equatable {
    let modifiedAt: Date?
    let fileSize: UInt64
    let contentHash: String
}

struct LoadedConfig {
    var document: ConfigDocument
    var settings: ClientSettings
    var revision: ConfigRevision
}

struct ConfigDocument: Equatable {
    private(set) var lines: [String]
    private let endedWithNewline: Bool

    init(raw: String) {
        self.endedWithNewline = raw.hasSuffix("\n")
        var parsed = raw.components(separatedBy: .newlines)
        if endedWithNewline, parsed.last == "" {
            parsed.removeLast()
        }
        self.lines = parsed
    }

    var rendered: String {
        lines.joined(separator: "\n") + (endedWithNewline ? "\n" : "")
    }

    func hasSection(_ section: String) -> Bool {
        lines.contains { Self.sectionName(in: $0)?.caseInsensitiveCompare(section) == .orderedSame }
    }

    func hasKey(_ key: String, section: String? = nil) -> Bool {
        value(for: key, section: section) != nil
    }

    func value(for key: String, section: String? = nil) -> String? {
        var currentSection: String?
        for line in lines {
            if let parsedSection = Self.sectionName(in: line) {
                currentSection = parsedSection
                continue
            }
            guard Self.sectionsMatch(currentSection, section),
                  let pair = Self.keyValue(in: line),
                  pair.key.caseInsensitiveCompare(key) == .orderedSame else {
                continue
            }
            return Self.unquote(pair.value)
        }
        return nil
    }

    mutating func set(_ value: String, for key: String, section: String? = nil) {
        var currentSection: String?
        var firstSectionIndex: Int?
        var targetSectionIndex: Int?
        var targetSectionEnd = lines.count

        for index in lines.indices {
            if let parsedSection = Self.sectionName(in: lines[index]) {
                if firstSectionIndex == nil { firstSectionIndex = index }
                if let section,
                   parsedSection.caseInsensitiveCompare(section) == .orderedSame {
                    targetSectionIndex = index
                    currentSection = parsedSection
                    continue
                }
                if targetSectionIndex != nil, targetSectionEnd == lines.count {
                    targetSectionEnd = index
                }
                currentSection = parsedSection
                continue
            }

            if Self.sectionsMatch(currentSection, section),
               let pair = Self.keyValue(in: lines[index]),
               pair.key.caseInsensitiveCompare(key) == .orderedSame {
                let prefix = lines[index].prefix { $0 == " " || $0 == "\t" }
                lines[index] = "\(prefix)\(key) = \(value)"
                return
            }
        }

        if let section {
            if let targetSectionIndex {
                let insertion = max(targetSectionIndex + 1, targetSectionEnd)
                lines.insert("\(key) = \(value)", at: insertion)
            } else {
                if lines.last?.isEmpty == false { lines.append("") }
                lines.append("[\(section)]")
                lines.append("\(key) = \(value)")
            }
        } else {
            let insertion = firstSectionIndex ?? lines.count
            lines.insert("\(key) = \(value)", at: insertion)
        }
    }

    private static func sectionName(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), trimmed.count > 2 else { return nil }
        return String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    private static func keyValue(in line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("#"),
              !trimmed.hasPrefix(";"),
              !trimmed.hasPrefix("[") else { return nil }
        guard let separator = trimmed.firstIndex(of: "=") else { return nil }
        let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
        let value = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    private static func sectionsMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs?, rhs?): return lhs.caseInsensitiveCompare(rhs) == .orderedSame
        default: return false
        }
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast())
    }
}

struct ConfigStore {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    static func detectedConfigURL(fileManager: FileManager = .default) -> URL {
        if let override = ProcessInfo.processInfo.environment["SEEKSYNC_CONFIG_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
        }
        let home = fileManager.homeDirectoryForCurrentUser
        let modern = home.appendingPathComponent(".config/sockseek/sockseek.conf")
        if fileManager.fileExists(atPath: modern.path) { return modern }
        let legacy = home.appendingPathComponent(".config/sldl/sldl.conf")
        if fileManager.fileExists(atPath: legacy.path) { return legacy }
        return modern
    }

    static func detectedBinaryPath(fileManager: FileManager = .default) -> String {
        if let override = ProcessInfo.processInfo.environment["SEEKSYNC_BINARY_PATH"], !override.isEmpty {
            return NSString(string: override).expandingTildeInPath
        }
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".local/bin/sockseek").path,
            "/opt/homebrew/bin/sockseek",
            "/usr/local/bin/sockseek",
            SockseekInstaller.managedBinaryURL(fileManager: fileManager).path
        ]
        return candidates.first(where: fileManager.isExecutableFile(atPath:))
            ?? SockseekInstaller.managedBinaryURL(fileManager: fileManager).path
    }

    func load(from url: URL, binaryPath: String? = nil, preferredProfile: String? = nil) throws -> LoadedConfig {
        guard fileManager.fileExists(atPath: url.path) else { throw ConfigStoreError.missing(url) }
        let raw: String
        do {
            raw = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ConfigStoreError.unreadable("Could not read \(url.path): \(error.localizedDescription)")
        }
        let document = ConfigDocument(raw: raw)
        let requestedProfile = preferredProfile?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let profile: String
        if !requestedProfile.isEmpty, document.hasSection(requestedProfile) {
            profile = requestedProfile
        } else {
            profile = document.hasSection("playlist") ? "playlist" : ""
        }
        let section: String? = profile.isEmpty ? nil : profile
        let preferredRaw = document.value(for: "pref-format", section: section)
            ?? document.value(for: "pref-format")
            ?? AudioPreference.mp3.rawValue
        let output = document.value(for: "output-dir", section: section)
            ?? document.value(for: "path", section: section)
            ?? document.value(for: "output-dir")
            ?? document.value(for: "path")
            ?? "~/Music/downloads"

        var settings = ClientSettings()
        settings.binaryPath = binaryPath ?? Self.detectedBinaryPath(fileManager: fileManager)
        settings.configPath = url.path
        settings.outputDirectory = output
        settings.preferredFormat = Self.audioPreference(from: preferredRaw)
        settings.preferredFormatRaw = preferredRaw
        settings.allowYouTubeFallback = Self.boolValue(
            document.value(for: "yt-dlp", section: section) ?? document.value(for: "yt-dlp"),
            default: false
        )
        settings.lookForPreferredQuality = Self.boolValue(
            document.value(for: "skip-check-pref-cond", section: section)
                ?? document.value(for: "skip-check-pref-cond"),
            default: true
        )
        settings.writeM3UPlaylist = Self.boolValue(
            document.value(for: "write-playlist", section: section)
                ?? document.value(for: "write-playlist"),
            default: true
        )
        settings.profileName = profile
        settings.soulseekUsername = document.value(for: "username") ?? ""
        settings.soulseekPassword = document.value(for: "password") ?? ""
        settings.spotifyClientID = document.value(for: "spotify-id") ?? ""
        settings.spotifyClientSecret = document.value(for: "spotify-secret") ?? ""
        settings.spotifyAccessToken = document.value(for: "spotify-token") ?? ""
        settings.spotifyRefreshToken = document.value(for: "spotify-refresh") ?? ""

        return LoadedConfig(document: document, settings: settings, revision: try revision(for: url))
    }

    func save(
        settings: ClientSettings,
        document original: ConfigDocument,
        to url: URL,
        expectedRevision: ConfigRevision?
    ) throws -> LoadedConfig {
        if fileManager.fileExists(atPath: url.path),
           expectedRevision == nil {
            throw ConfigStoreError.existingFileWasNotLoaded
        }
        if fileManager.fileExists(atPath: url.path),
           let expectedRevision,
           try revision(for: url) != expectedRevision {
                throw ConfigStoreError.externallyModified
        }

        var document = original
        let profile: String? = settings.profileName.isEmpty ? nil : settings.profileName
        let outputKey: String
        if document.hasKey("output-dir", section: profile) {
            outputKey = "output-dir"
        } else if document.hasKey("path", section: profile) {
            outputKey = "path"
        } else {
            outputKey = "output-dir"
        }

        document.set(settings.outputDirectory, for: outputKey, section: profile)
        document.set(settings.preferredFormatValue, for: "pref-format", section: profile)
        document.set(settings.lookForPreferredQuality ? "true" : "false", for: "skip-check-pref-cond", section: profile)
        document.set(settings.writeM3UPlaylist ? "true" : "false", for: "write-playlist", section: profile)
        let youtubeSection = document.hasKey("yt-dlp", section: profile) ? profile : nil
        document.set(settings.allowYouTubeFallback ? "true" : "false", for: "yt-dlp", section: youtubeSection)

        setCredential(settings.soulseekUsername, key: "username", in: &document)
        setCredential(settings.soulseekPassword, key: "password", in: &document)
        setCredential(settings.spotifyClientID, key: "spotify-id", in: &document)
        setCredential(settings.spotifyClientSecret, key: "spotify-secret", in: &document)
        setCredential(settings.spotifyAccessToken, key: "spotify-token", in: &document)
        setCredential(settings.spotifyRefreshToken, key: "spotify-refresh", in: &document)

        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: url.path) {
            let backup = URL(fileURLWithPath: url.path + ".seeksync-backup")
            if !fileManager.fileExists(atPath: backup.path) {
                try fileManager.copyItem(at: url, to: backup)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
            }
        }
        try document.rendered.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return try load(from: url, binaryPath: settings.binaryPath, preferredProfile: settings.profileName)
    }

    private func revision(for url: URL) throws -> ConfigRevision {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return ConfigRevision(
            modifiedAt: attributes[.modificationDate] as? Date,
            fileSize: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            contentHash: SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func setCredential(_ value: String, key: String, in document: inout ConfigDocument) {
        guard !value.isEmpty || document.hasKey(key) else { return }
        document.set(value, for: key)
    }

    private static func boolValue(_ raw: String?, default defaultValue: Bool) -> Bool {
        guard let raw else { return defaultValue }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on": return true
        case "0", "false", "no", "off": return false
        default: return defaultValue
        }
    }

    private static func audioPreference(from raw: String) -> AudioPreference {
        if let exact = AudioPreference(rawValue: raw.lowercased()) { return exact }
        let values = raw.lowercased().split(separator: ",").map(String.init)
        for preference in AudioPreference.allCases where preference != .any {
            if values.contains(preference.rawValue) { return preference }
        }
        return .any
    }
}
