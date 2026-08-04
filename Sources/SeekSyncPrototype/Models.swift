import Foundation

enum AppSection: String, CaseIterable, Identifiable, Codable {
    case playlists = "Playlists"
    case syncPool = "Sync Pool"
    case activity = "Activity"
    case attention = "Needs Attention"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .playlists: return "music.note.list"
        case .syncPool: return "arrow.triangle.2.circlepath"
        case .activity: return "clock.arrow.circlepath"
        case .attention: return "exclamationmark.triangle"
        case .settings: return "gearshape"
        }
    }
}

enum PlaylistHealth: String, Codable {
    case ready
    case partial
    case attention
    case neverSynced

    var label: String {
        switch self {
        case .ready: return "Up to date"
        case .partial: return "Missing tracks"
        case .attention: return "Needs attention"
        case .neverSynced: return "Not synced"
        }
    }
}

struct Playlist: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var owner: String
    var detail: String
    var spotifyURL: String
    var artworkURL: URL?
    var artworkHue: Double
    var trackCount: Int
    var localCount: Int
    var upgradeCandidates: Int
    var needsReview: Int
    var lastSyncedAt: Date?
    var health: PlaylistHealth
    var isFixture: Bool?

    var missingCount: Int { max(trackCount - localCount, 0) }
    var coverage: Double {
        guard trackCount > 0 else { return 0 }
        return min(Double(localCount) / Double(trackCount), 1)
    }

    mutating func applySyncOutcome(phase: RunPhase, counts: RunCounts, at date: Date = Date()) {
        lastSyncedAt = date
        let resolved = counts.added + counts.upgraded + counts.alreadyBest
        let observedTotal = resolved + counts.unavailable + counts.needsReview
        if trackCount == 0, observedTotal > 0 {
            trackCount = observedTotal
        }
        if observedTotal > 0 {
            localCount = min(trackCount, resolved)
        } else if phase == .completed {
            localCount = trackCount
        }

        switch phase {
        case .completed:
            health = .ready
            needsReview = 0
            upgradeCandidates = 0
        case .partial:
            health = counts.needsReview > 0 ? .attention : .partial
            needsReview = counts.needsReview
        case .failed:
            health = .attention
        default:
            break
        }
    }

    func preservingSyncState(from previous: Playlist?) -> Playlist {
        guard let previous else { return self }
        var merged = self
        if merged.trackCount == 0, previous.trackCount > 0 {
            merged.trackCount = previous.trackCount
        }
        merged.localCount = min(previous.localCount, merged.trackCount)
        merged.upgradeCandidates = previous.upgradeCandidates
        merged.needsReview = previous.needsReview
        merged.lastSyncedAt = previous.lastSyncedAt
        merged.health = previous.health
        if previous.health == .ready, merged.localCount < merged.trackCount {
            merged.health = .partial
        }
        return merged
    }

    static let samples: [Playlist] = [
        Playlist(
            id: "midnight-drive",
            name: "Midnight Drive",
            owner: "Theo",
            detail: "Warm synths, late-night house, and long freeway lights.",
            spotifyURL: "https://open.spotify.com/playlist/SeekSyncFixtureA001",
            artworkURL: nil,
            artworkHue: 0.72,
            trackCount: 84,
            localCount: 82,
            upgradeCandidates: 3,
            needsReview: 0,
            lastSyncedAt: Date().addingTimeInterval(-6_200),
            health: .partial,
            isFixture: true
        ),
        Playlist(
            id: "discover-weekly",
            name: "Discover Weekly",
            owner: "Spotify",
            detail: "A weekly mix of new-to-you music.",
            spotifyURL: "https://open.spotify.com/playlist/SeekSyncFixtureB002",
            artworkURL: nil,
            artworkHue: 0.34,
            trackCount: 30,
            localCount: 0,
            upgradeCandidates: 0,
            needsReview: 0,
            lastSyncedAt: nil,
            health: .neverSynced,
            isFixture: true
        ),
        Playlist(
            id: "rekordbox-warm-up",
            name: "Rekordbox · Warm Up",
            owner: "Theo",
            detail: "Low-slung openers and patient dance-floor builders.",
            spotifyURL: "https://open.spotify.com/playlist/SeekSyncFixtureC003",
            artworkURL: nil,
            artworkHue: 0.08,
            trackCount: 112,
            localCount: 112,
            upgradeCandidates: 0,
            needsReview: 1,
            lastSyncedAt: Date().addingTimeInterval(-86_400),
            health: .attention,
            isFixture: true
        ),
        Playlist(
            id: "deep-house-ids",
            name: "Deep House IDs",
            owner: "Theo",
            detail: "Long-running crate of finds, promos, and white labels.",
            spotifyURL: "https://open.spotify.com/playlist/SeekSyncFixtureD004",
            artworkURL: nil,
            artworkHue: 0.56,
            trackCount: 237,
            localCount: 211,
            upgradeCandidates: 9,
            needsReview: 2,
            lastSyncedAt: Date().addingTimeInterval(-259_200),
            health: .partial,
            isFixture: true
        ),
        Playlist(
            id: "release-radar",
            name: "Release Radar",
            owner: "Spotify",
            detail: "New releases from artists you follow.",
            spotifyURL: "https://open.spotify.com/playlist/SeekSyncFixtureE005",
            artworkURL: nil,
            artworkHue: 0.95,
            trackCount: 30,
            localCount: 28,
            upgradeCandidates: 1,
            needsReview: 0,
            lastSyncedAt: Date().addingTimeInterval(-432_000),
            health: .attention,
            isFixture: true
        ),
        Playlist(
            id: "sunday-kitchen",
            name: "Sunday Kitchen",
            owner: "Theo",
            detail: "Soul, Brazilian jazz, and records for cooking slowly.",
            spotifyURL: "https://open.spotify.com/playlist/SeekSyncFixtureF006",
            artworkURL: nil,
            artworkHue: 0.15,
            trackCount: 61,
            localCount: 61,
            upgradeCandidates: 2,
            needsReview: 0,
            lastSyncedAt: Date().addingTimeInterval(-604_800),
            health: .ready,
            isFixture: true
        )
    ]
}

enum SyncExecutionKind: Equatable {
    case previewOnly
    case sockseek
}

extension Playlist {
    var executionKind: SyncExecutionKind {
        isFixture == true ? .previewOnly : .sockseek
    }
}

enum PlaylistLibrary {
    struct RefreshResult {
        let catalog: [Playlist]
        let remainingImports: [Playlist]
    }

    static func merged(imported: [Playlist], catalog: [Playlist]) -> [Playlist] {
        let catalogIDs = Set(catalog.map(\.id))
        return imported.filter { !catalogIDs.contains($0.id) } + catalog
    }

    static func indexedByID(_ playlists: [Playlist]) -> [String: Playlist] {
        playlists.reduce(into: [:]) { indexed, playlist in
            if indexed[playlist.id] == nil { indexed[playlist.id] = playlist }
        }
    }

    static func refreshed(
        catalog incoming: [Playlist],
        previousCatalog: [Playlist],
        imported: [Playlist]
    ) -> RefreshResult {
        let previousByID = indexedByID(previousCatalog + imported)
        let catalog = incoming.map { $0.preservingSyncState(from: previousByID[$0.id]) }
        let catalogIDs = Set(catalog.map(\.id))
        return RefreshResult(
            catalog: catalog,
            remainingImports: imported.filter { !catalogIDs.contains($0.id) }
        )
    }
}

enum YouTubePolicy: String, CaseIterable, Identifiable, Codable {
    case inherit = "Inherit"
    case allow = "Allow"
    case never = "Never"

    var id: String { rawValue }
}

struct SyncPlan: Identifiable, Hashable, Codable {
    let id: UUID
    let playlistID: String
    var enabled: Bool
    var youtubePolicy: YouTubePolicy
    var nextRunAt: Date
    var lastRunAt: Date?

    init(
        id: UUID = UUID(),
        playlistID: String,
        enabled: Bool = true,
        youtubePolicy: YouTubePolicy = .inherit,
        nextRunAt: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86_400),
        lastRunAt: Date? = nil
    ) {
        self.id = id
        self.playlistID = playlistID
        self.enabled = enabled
        self.youtubePolicy = youtubePolicy
        self.nextRunAt = nextRunAt
        self.lastRunAt = lastRunAt
    }
}

enum SyncTrigger: String, Codable {
    case manual = "Manual"
    case scheduled = "Scheduled"
    case retry = "Retry"
}

enum RunPhase: String, Codable {
    case queued = "Queued"
    case refreshing = "Refreshing Spotify"
    case searching = "Searching Soulseek"
    case downloading = "Downloading"
    case verifying = "Verifying"
    case completed = "Completed"
    case partial = "Completed with issues"
    case failed = "Failed"
    case cancelled = "Cancelled"

    var isActive: Bool {
        switch self {
        case .queued, .refreshing, .searching, .downloading, .verifying: return true
        default: return false
        }
    }
}

struct RunCounts: Codable, Hashable {
    var added = 0
    var upgraded = 0
    var alreadyBest = 0
    var unavailable = 0
    var needsReview = 0
}

struct SyncRun: Identifiable, Hashable, Codable {
    let id: UUID
    let playlistID: String
    let playlistName: String
    let trigger: SyncTrigger
    var phase: RunPhase
    var progress: Double
    var startedAt: Date
    var finishedAt: Date?
    var counts: RunCounts
    var progressDetails: SyncProgressSnapshot?
    var message: String
    var commandPreview: String

    init(
        id: UUID = UUID(),
        playlistID: String,
        playlistName: String,
        trigger: SyncTrigger,
        phase: RunPhase = .queued,
        progress: Double = 0,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        counts: RunCounts = RunCounts(),
        progressDetails: SyncProgressSnapshot? = nil,
        message: String = "Waiting to start",
        commandPreview: String
    ) {
        self.id = id
        self.playlistID = playlistID
        self.playlistName = playlistName
        self.trigger = trigger
        self.phase = phase
        self.progress = progress
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.counts = counts
        self.progressDetails = progressDetails
        self.message = message
        self.commandPreview = commandPreview
    }
}

enum AudioPreference: String, CaseIterable, Identifiable, Codable {
    case flac
    case mp3
    case opus
    case m4a
    case wav
    case any = "mp3,flac,ogg,m4a,opus,wav,aac,alac"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .flac: return "FLAC preferred"
        case .mp3: return "MP3 preferred"
        case .opus: return "Opus preferred"
        case .m4a: return "M4A preferred"
        case .wav: return "WAV preferred"
        case .any: return "Any common audio"
        }
    }
}

struct ClientSettings: Codable, Equatable {
    var binaryPath = ""
    var configPath = ""
    var outputDirectory = "~/Music/downloads"
    var preferredFormat: AudioPreference = .flac
    var preferredFormatRaw: String?
    var allowYouTubeFallback = true
    var lookForPreferredQuality = true
    var writeM3UPlaylist = true
    var profileName = "playlist"
    var dailyHour = 2
    var dailyMinute = 0
    var liveSchedulingArmed: Bool?

    var soulseekUsername = ""
    var soulseekPassword = ""
    var spotifyClientID = ""
    var spotifyClientSecret = ""
    var spotifyAccessToken = ""
    var spotifyRefreshToken = ""

    var preferredFormatValue: String {
        let raw = preferredFormatRaw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? preferredFormat.rawValue : raw
    }

    var preferredFormatLabel: String {
        "\(preferredFormatValue.uppercased()) preferred"
    }

    var isLiveSchedulingArmed: Bool { liveSchedulingArmed == true }

    var canLoadSpotifyLibrary: Bool {
        if !spotifyAccessToken.isEmpty { return true }
        return !spotifyClientID.isEmpty
            && !spotifyClientSecret.isEmpty
            && !spotifyRefreshToken.isEmpty
    }
}

enum DependencyState: Equatable {
    case ready(version: String)
    case missing
    case checking
    case installing
    case failed(String)

    var label: String {
        switch self {
        case .ready(let version): return "Sockseek \(version) ready"
        case .missing: return "Sockseek not found"
        case .checking: return "Checking Sockseek…"
        case .installing: return "Installing Sockseek 3.0.4…"
        case .failed(let reason): return reason
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

enum SpotifyConnectionState: Equatable {
    case demo
    case cached(count: Int)
    case loading
    case connected(account: String)
    case failed(String)

    var label: String {
        switch self {
        case .demo: return "Demo Spotify library"
        case .cached(let count): return "Spotify catalog · \(count) \(count == 1 ? "playlist" : "playlists")"
        case .loading: return "Refreshing Spotify…"
        case .connected(let account): return "Spotify · \(account)"
        case .failed: return "Spotify needs attention"
        }
    }
}

struct SLDLCommand: Equatable {
    let executable: String
    let arguments: [String]

    var displayString: String {
        ([executable] + arguments).map(Self.shellQuote).joined(separator: " ")
    }

    private static func shellQuote(_ value: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._/~:"))
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct PrototypeState: Codable {
    var importedPlaylists: [Playlist]
    var cachedSpotifyPlaylists: [Playlist]?
    var plans: [SyncPlan]
    var runs: [SyncRun]
    var settings: ClientSettings
}

extension Date {
    var relativeLabel: String {
        RelativeDateTimeFormatter.prototype.localizedString(for: self, relativeTo: Date())
    }

    var shortDateTimeLabel: String {
        DateFormatter.prototypeShort.string(from: self)
    }
}

private extension RelativeDateTimeFormatter {
    static let prototype: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

private extension DateFormatter {
    static let prototypeShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
