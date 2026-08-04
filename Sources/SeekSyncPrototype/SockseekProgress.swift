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

struct SockseekProgressTracker {
    private(set) var snapshot = SyncProgressSnapshot()
    private(set) var counts = RunCounts()

    private var positionsByTrack: [String: Int] = [:]

    mutating func consume(_ chunk: String) {
        let decoder = JSONDecoder()
        for line in chunk.split(whereSeparator: \.isNewline) {
            guard let data = line.data(using: .utf8),
                  let event = try? decoder.decode(SockseekProgressEvent.self, from: data) else { continue }
            consume(event)
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
                    positionsByTrack[key] = index + 1
                }
                recordTerminal(
                    lifecycleState: track.lifecycleState,
                    terminalOutcome: track.terminalOutcome,
                    skipReason: track.skipReason
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
            recordTerminal(
                lifecycleState: data.lifecycleState,
                terminalOutcome: data.terminalOutcome,
                skipReason: data.skipReason
            )
            let currentKey = snapshot.currentTrack.flatMap { trackKey(artist: $0.artist, title: $0.title) }
            if key == nil || key == currentKey {
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
            position: key.flatMap { positionsByTrack[$0] },
            artist: artist,
            title: title,
            activity: activity,
            bytesTransferred: nil,
            totalBytes: data.size,
            downloadFraction: nil
        )
    }

    private mutating func recordTerminal(
        lifecycleState: String?,
        terminalOutcome: String?,
        skipReason: String?
    ) {
        guard let delta = AppModel.terminalCounts(
            lifecycleState: lifecycleState,
            terminalOutcome: terminalOutcome,
            skipReason: skipReason
        ) else { return }
        snapshot.completedTracks += 1
        if snapshot.totalTracks > 0 {
            snapshot.completedTracks = min(snapshot.completedTracks, snapshot.totalTracks)
        }
        counts.add(delta)
    }

    private func trackKey(artist: String?, title: String?) -> String? {
        guard let artist, let title else { return nil }
        return "\(artist.lowercased())\u{1F}\(title.lowercased())"
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
    let lifecycleState: String?
    let terminalOutcome: String?
    let skipReason: String?
    let size: Int64?
    let bytesTransferred: Int64?
    let totalBytes: Int64?
    let percent: Double?
}

struct SockseekTrackProgress: Decodable {
    let index: Int?
    let artist: String?
    let title: String?
    let lifecycleState: String?
    let terminalOutcome: String?
    let skipReason: String?
}
