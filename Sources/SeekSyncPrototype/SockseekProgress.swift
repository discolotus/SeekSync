import Foundation

enum TrackSyncActivity: String, Codable, Hashable {
    case searching = "Searching"
    case downloading = "Downloading"
}

struct CurrentTrackProgress: Codable, Hashable {
    var position: Int?
    var artist: String
    var title: String
    var activity: TrackSyncActivity
    var bytesTransferred: Int64?
    var totalBytes: Int64?
    var downloadFraction: Double?
}

struct SyncProgressSnapshot: Codable, Hashable {
    var totalTracks = 0
    var completedTracks = 0
    var currentTrack: CurrentTrackProgress?

    var playlistFraction: Double {
        guard totalTracks > 0 else { return 0 }
        return min(Double(completedTracks) / Double(totalTracks), 1)
    }
}

enum TrackFailureSource: String, Codable, Hashable {
    case soulseek
    case youtubeFallback
    case soulseekAndYouTube
    case cachedPreviousResult
    case unknown

    var label: String {
        switch self {
        case .soulseek: return "Soulseek"
        case .youtubeFallback: return "YouTube via yt-dlp"
        case .soulseekAndYouTube: return "Soulseek + yt-dlp"
        case .cachedPreviousResult: return "Previous sync result"
        case .unknown: return "Source not reported"
        }
    }

    var systemImage: String {
        switch self {
        case .soulseek: return "network"
        case .youtubeFallback: return "play.rectangle.fill"
        case .soulseekAndYouTube: return "arrow.triangle.branch"
        case .cachedPreviousResult: return "clock.arrow.circlepath"
        case .unknown: return "questionmark.circle"
        }
    }
}

struct TrackSyncFailure: Codable, Hashable, Identifiable {
    var position: Int?
    var artist: String
    var title: String
    var album: String?
    var terminalOutcome: String?
    var failureReason: String?
    var skipReason: String?
    var rawResultCount: Int?
    var lockedCount: Int?
    var source: TrackFailureSource?
    var failureMessage: String?

    init(
        position: Int?,
        artist: String,
        title: String,
        album: String? = nil,
        terminalOutcome: String?,
        failureReason: String?,
        skipReason: String?,
        rawResultCount: Int?,
        lockedCount: Int?,
        source: TrackFailureSource? = nil,
        failureMessage: String? = nil
    ) {
        self.position = position
        self.artist = artist
        self.title = title
        self.album = album
        self.terminalOutcome = terminalOutcome
        self.failureReason = failureReason
        self.skipReason = skipReason
        self.rawResultCount = rawResultCount
        self.lockedCount = lockedCount
        self.source = source
        self.failureMessage = failureMessage
    }

    var id: String {
        "\(position ?? -1)\u{1F}\(artist.lowercased())\u{1F}\(title.lowercased())\u{1F}\(failureReason ?? skipReason ?? terminalOutcome ?? "unknown")"
    }

    var reasonDescription: String {
        if normalized(terminalOutcome) == "skipped" {
            switch normalized(skipReason) {
            case "previouslynotfound", "notfoundlasttime":
                return "Skipped because an earlier sync found no matching file."
            case let reason? where !reason.isEmpty && reason != "none":
                return "Sockseek skipped this track: \(Self.humanized(skipReason ?? reason))."
            default:
                break
            }
        }

        switch normalized(failureReason) {
        case "invalidsearchstring":
            return "The artist and title could not produce a valid search."
        case "outofdownloadretries":
            return source == .youtubeFallback
                ? "The YouTube/yt-dlp fallback exhausted its download retries."
                : "Soulseek download retries were exhausted."
        case "alldownloadsfailed":
            return source == .youtubeFallback
                ? "The YouTube result was found, but the yt-dlp download failed."
                : "Soulseek files were found, but every download attempt failed."
        case "extractionfailed":
            return "Sockseek could not extract this track from the playlist."
        case "cancelled":
            return "The track was cancelled before it completed."
        case "childjobsfailed":
            return "A required Sockseek subtask failed."
        case "nosearchresults":
            if source == .soulseekAndYouTube {
                return "Soulseek found no file, and yt-dlp found no usable YouTube result."
            }
            if source == .youtubeFallback {
                return "The YouTube/yt-dlp fallback found no usable result."
            }
            if let lockedCount, lockedCount > 0 {
                if let rawResultCount, rawResultCount > lockedCount {
                    return "\(rawResultCount) Soulseek results were found, but no downloadable file was available (\(lockedCount) locked)."
                }
                return "Only \(lockedCount) locked \(lockedCount == 1 ? "result was" : "results were") found; no downloadable file was available."
            }
            return source == .soulseek
                ? "No Soulseek file results were found. YouTube fallback was disabled for this run."
                : "No Soulseek file results were found."
        case "nomatchingresults":
            if source == .soulseekAndYouTube {
                return "Soulseek results did not match this track, and yt-dlp found no usable YouTube result."
            }
            if source == .youtubeFallback {
                return "The YouTube/yt-dlp fallback found results, but none were usable for this track."
            }
            if let rawResultCount, rawResultCount > 0 {
                return "\(rawResultCount) Soulseek \(rawResultCount == 1 ? "result was" : "results were") found, but none matched this track's requirements."
            }
            return "Soulseek returned results, but none matched this track's requirements."
        case "other":
            if source == .youtubeFallback {
                return cleanedFailureMessage.map { "The YouTube/yt-dlp fallback failed: \($0)" }
                    ?? "The YouTube/yt-dlp fallback failed without a specific reason."
            }
            return cleanedFailureMessage ?? "Sockseek reported an unspecified error."
        case let reason? where !reason.isEmpty && reason != "none":
            return "Sockseek reported: \(Self.humanized(failureReason ?? reason))."
        default:
            break
        }

        if normalized(terminalOutcome) == "failed" {
            return "Sockseek reported a failure without a specific reason."
        }
        return "Sockseek could not resolve this track and did not provide a specific reason."
    }

    private var cleanedFailureMessage: String? {
        guard let message = failureMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else { return nil }
        return message
    }

    private func normalized(_ value: String?) -> String? {
        value?.lowercased().filter(\.isLetter)
    }

    private static func humanized(_ value: String) -> String {
        let withSpaces = value.replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
        return withSpaces.replacingOccurrences(of: "_", with: " ").lowercased()
    }
}

struct SockseekProgressTracker {
    private(set) var snapshot = SyncProgressSnapshot()
    private(set) var counts = RunCounts()
    private(set) var failures: [TrackSyncFailure] = []

    private var positionsByTrack: [String: [Int]] = [:]
    private var albumsByPosition: [Int: String] = [:]
    private var terminalPositions: Set<Int> = []
    private var unpositionedTerminalKeys: Set<String> = []
    private var fallbackAttemptedTrackKeys: Set<String> = []
    private let youtubeFallbackEnabled: Bool?

    init(youtubeFallbackEnabled: Bool? = nil) {
        self.youtubeFallbackEnabled = youtubeFallbackEnabled
    }

    mutating func consume(_ chunk: String) {
        let decoder = JSONDecoder()
        for line in chunk.split(whereSeparator: \.isNewline) {
            if let data = line.data(using: .utf8),
               let event = try? decoder.decode(SockseekProgressEvent.self, from: data) {
                consume(event)
            } else if line.localizedCaseInsensitiveContains("running fallback:"),
                      let currentTrack = snapshot.currentTrack,
                      let key = trackKey(artist: currentTrack.artist, title: currentTrack.title) {
                fallbackAttemptedTrackKeys.insert(key)
            }
        }
    }

    private mutating func consume(_ event: SockseekProgressEvent) {
        guard let data = event.data else { return }
        switch event.type {
        case "track_list":
            snapshot.totalTracks = max(snapshot.totalTracks, data.total ?? 0)
            for track in data.tracks ?? [] {
                let key = trackKey(artist: track.artist, title: track.title)
                if let key, let index = track.index {
                    positionsByTrack[key, default: []].append(index + 1)
                    if let album = normalizedMetadata(track.album) {
                        albumsByPosition[index + 1] = album
                    }
                }
                recordTerminal(
                    position: track.index.map { $0 + 1 },
                    artist: track.artist,
                    title: track.title,
                    album: track.album,
                    lifecycleState: track.lifecycleState,
                    activityPhase: track.activityPhase,
                    terminalOutcome: track.terminalOutcome,
                    skipReason: track.skipReason,
                    failureReason: track.failureReason,
                    rawResultCount: track.rawResultCount,
                    lockedCount: track.lockedCount,
                    downloadSource: track.downloadSource,
                    failureMessage: track.failureMessage
                )
            }
        case "search_start":
            setCurrentTrack(from: data, activity: .searching)
        case "download_start":
            setCurrentTrack(from: data, activity: .downloading)
            snapshot.currentTrack?.totalBytes = data.size
        case "download_progress":
            guard snapshot.currentTrack != nil else { return }
            snapshot.currentTrack?.activity = .downloading
            snapshot.currentTrack?.bytesTransferred = data.bytesTransferred
            snapshot.currentTrack?.totalBytes = data.totalBytes
            if let bytes = data.bytesTransferred, let total = data.totalBytes, total > 0 {
                snapshot.currentTrack?.downloadFraction = min(max(Double(bytes) / Double(total), 0), 1)
            } else if let percent = data.percent {
                snapshot.currentTrack?.downloadFraction = min(max(percent / 100, 0), 1)
            }
        case "track_state":
            let key = trackKey(artist: data.artist, title: data.title)
            if normalized(data.activityPhase) == "runningfallback", let key {
                fallbackAttemptedTrackKeys.insert(key)
            }
            let position = nextUnfinishedPosition(for: key)
            if position != nil || key.flatMap({ positionsByTrack[$0] }) == nil {
                recordTerminal(
                    position: position,
                    artist: data.artist,
                    title: data.title,
                    album: data.album,
                    lifecycleState: data.lifecycleState,
                    activityPhase: data.activityPhase,
                    terminalOutcome: data.terminalOutcome,
                    skipReason: data.skipReason,
                    failureReason: data.failureReason,
                    rawResultCount: data.rawResultCount,
                    lockedCount: data.lockedCount,
                    downloadSource: data.downloadSource,
                    failureMessage: data.failureMessage
                )
            }
            let currentKey = snapshot.currentTrack.flatMap { trackKey(artist: $0.artist, title: $0.title) }
            if normalized(data.lifecycleState) == "terminal", (key == nil || key == currentKey) {
                snapshot.currentTrack = nil
            }
        default:
            break
        }
    }

    private mutating func setCurrentTrack(from data: SockseekProgressData, activity: TrackSyncActivity) {
        let artist = data.artist ?? "Unknown artist"
        let title = data.title ?? "Unknown track"
        let key = trackKey(artist: data.artist, title: data.title)
        snapshot.currentTrack = CurrentTrackProgress(
            position: nextUnfinishedPosition(for: key),
            artist: artist,
            title: title,
            activity: activity,
            bytesTransferred: nil,
            totalBytes: data.size,
            downloadFraction: nil
        )
    }

    private mutating func recordTerminal(
        position: Int?,
        artist: String?,
        title: String?,
        album: String?,
        lifecycleState: String?,
        activityPhase: String?,
        terminalOutcome: String?,
        skipReason: String?,
        failureReason: String?,
        rawResultCount: Int?,
        lockedCount: Int?,
        downloadSource: String?,
        failureMessage: String?
    ) {
        guard let delta = AppModel.terminalCounts(
            lifecycleState: lifecycleState,
            terminalOutcome: terminalOutcome,
            skipReason: skipReason
        ) else { return }

        let unpositionedKey = [
            trackKey(artist: artist, title: title) ?? "unknown",
            terminalOutcome ?? "unknown",
            failureReason ?? "none",
            skipReason ?? "none"
        ].joined(separator: "\u{1F}")
        if let position {
            guard terminalPositions.insert(position).inserted else { return }
        } else {
            guard unpositionedTerminalKeys.insert(unpositionedKey).inserted else { return }
        }

        snapshot.completedTracks += 1
        if snapshot.totalTracks > 0 {
            snapshot.completedTracks = min(snapshot.completedTracks, snapshot.totalTracks)
        }
        counts.add(delta)
        if delta.unavailable > 0 || delta.needsReview > 0 {
            failures.append(
                TrackSyncFailure(
                    position: position,
                    artist: artist ?? "Unknown artist",
                    title: title ?? "Unknown track",
                    album: normalizedMetadata(album) ?? position.flatMap { albumsByPosition[$0] },
                    terminalOutcome: terminalOutcome,
                    failureReason: failureReason,
                    skipReason: skipReason,
                    rawResultCount: rawResultCount,
                    lockedCount: lockedCount,
                    source: failureSource(
                        artist: artist,
                        title: title,
                        activityPhase: activityPhase,
                        terminalOutcome: terminalOutcome,
                        failureReason: failureReason,
                        skipReason: skipReason,
                        downloadSource: downloadSource
                    ),
                    failureMessage: failureMessage
                )
            )
        }
    }

    private func failureSource(
        artist: String?,
        title: String?,
        activityPhase: String?,
        terminalOutcome: String?,
        failureReason: String?,
        skipReason: String?,
        downloadSource: String?
    ) -> TrackFailureSource {
        let normalizedDownloadSource = normalized(downloadSource)
        if normalizedDownloadSource == "fallback" || normalizedDownloadSource == "ytdlp" {
            return .youtubeFallback
        }
        if normalizedDownloadSource == "soulseek" {
            return .soulseek
        }
        if normalized(terminalOutcome) == "skipped",
           ["previouslynotfound", "notfoundlasttime"].contains(normalized(skipReason) ?? "") {
            return .cachedPreviousResult
        }

        let key = trackKey(artist: artist, title: title)
        let fallbackAttempted = normalized(activityPhase) == "runningfallback"
            || key.map(fallbackAttemptedTrackKeys.contains) == true
        let reason = normalized(failureReason)
        if fallbackAttempted {
            return reason == "nosearchresults" || reason == "nomatchingresults"
                ? .soulseekAndYouTube
                : .youtubeFallback
        }
        if reason == "nosearchresults" || reason == "nomatchingresults" {
            if youtubeFallbackEnabled == true { return .soulseekAndYouTube }
            if youtubeFallbackEnabled == false { return .soulseek }
        }
        if reason == "outofdownloadretries" || reason == "alldownloadsfailed" {
            return .soulseek
        }
        return .unknown
    }

    private func nextUnfinishedPosition(for key: String?) -> Int? {
        guard let key else { return nil }
        return positionsByTrack[key]?.first { !terminalPositions.contains($0) }
    }

    private func trackKey(artist: String?, title: String?) -> String? {
        guard let artist, let title else { return nil }
        return "\(artist.lowercased())\u{1F}\(title.lowercased())"
    }

    private func normalized(_ value: String?) -> String? {
        value?.lowercased().filter(\.isLetter)
    }

    private func normalizedMetadata(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

struct SockseekProgressEvent: Decodable {
    let type: String
    let data: SockseekProgressData?
}

struct SockseekProgressData: Decodable {
    let total: Int?
    let tracks: [SockseekTrackProgress]?
    let index: Int?
    let artist: String?
    let title: String?
    let album: String?
    let lifecycleState: String?
    let activityPhase: String?
    let terminalOutcome: String?
    let skipReason: String?
    let failureReason: String?
    let size: Int64?
    let bytesTransferred: Int64?
    let totalBytes: Int64?
    let percent: Double?
    let rawResultCount: Int?
    let lockedCount: Int?
    let downloadSource: String?
    let failureMessage: String?
}

struct SockseekTrackProgress: Decodable {
    let index: Int?
    let artist: String?
    let title: String?
    let album: String?
    let lifecycleState: String?
    let activityPhase: String?
    let terminalOutcome: String?
    let skipReason: String?
    let failureReason: String?
    let rawResultCount: Int?
    let lockedCount: Int?
    let downloadSource: String?
    let failureMessage: String?
}
