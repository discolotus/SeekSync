import Foundation

/// Whether a track already exists somewhere the user owns, and whether the
/// generated playlist can point at it.
///
/// The distinction the inventory exists to make is `referenced` versus
/// `belowTarget`: both mean "you already own this", but only the first can be
/// brought into a playlist as it stands. A below-target file is left alone and
/// a sync looks for a replacement instead.
enum LibraryInventoryAvailability: String, CaseIterable, Hashable {
    case referenced
    case belowTarget
    case downloaded
    case missing
    case unavailable

    init(_ disposition: PlaylistTrackDisposition) {
        switch disposition {
        case .libraryReference: self = .referenced
        case .libraryBelowThreshold: self = .belowTarget
        case .downloaded: self = .downloaded
        case .downloadRequired: self = .missing
        case .unavailable, .unknown: self = .unavailable
        }
    }

    var label: String {
        switch self {
        case .referenced: return "In your library"
        case .belowTarget: return "Below target"
        case .downloaded: return "In downloads"
        case .missing: return "Not local yet"
        case .unavailable: return "Unresolved"
        }
    }

    /// The answer to "can this be brought into the playlist as it stands?"
    var playlistEligibility: String {
        switch self {
        case .referenced:
            return "The playlist links to this file where it already lives. Nothing is copied or downloaded."
        case .belowTarget:
            return "You already own this, but it misses the reuse conditions, so a sync looks for a replacement instead of linking it."
        case .downloaded:
            return "Already in SeekSync's downloads folder from an earlier sync."
        case .missing:
            return "No local copy was found. A confirmed sync would search for it."
        case .unavailable:
            return "No usable local or downloaded file could be established."
        }
    }

    /// Whether the row should spell out the eligibility rather than leave the
    /// state chip to speak for itself. "You own this but it cannot be linked"
    /// and "you own this and it will be linked" are the two answers a chip
    /// alone does not give; the rest repeat their own label.
    var explainsEligibilityInline: Bool {
        self == .referenced || self == .belowTarget
    }

    /// Ranked best-to-worst so a track appearing in several playlists reports
    /// its most usable state, with the disagreement flagged separately.
    fileprivate var rank: Int {
        switch self {
        case .referenced: return 0
        case .downloaded: return 1
        case .belowTarget: return 2
        case .missing: return 3
        case .unavailable: return 4
        }
    }

    /// Listing order. A file you own that cannot be linked is the finding worth
    /// leading with; settled tracks sink to the bottom.
    fileprivate var sortPriority: Int {
        switch self {
        case .belowTarget: return 0
        case .missing: return 1
        case .unavailable: return 2
        case .referenced: return 3
        case .downloaded: return 4
        }
    }
}

/// One track, gathered from every playlist inventory that mentions it.
struct LibraryInventoryEntry: Identifiable, Hashable {
    var id: String
    var artist: String
    var title: String
    var album: String?
    var lengthSeconds: Int?
    var availability: LibraryInventoryAvailability
    var localPath: String?
    var quality: AudioFileQuality?
    var playlistNames: [String]
    /// True when playlists disagree, which happens when they were analyzed
    /// under different reuse conditions.
    var variesByPlaylist: Bool

    var isSharedAcrossPlaylists: Bool { playlistNames.count > 1 }

    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let haystack = [artist, title, album ?? "", localPath ?? ""] + playlistNames
        return haystack.contains { $0.localizedCaseInsensitiveContains(trimmed) }
    }
}

/// A cross-playlist view of every analyzed track.
///
/// Per-playlist inventories answer "what will this sync do?". This answers the
/// question that spans them: "what do I already own, and where?"
struct LibraryInventory {
    var entries: [LibraryInventoryEntry]
    var playlistCount: Int
    var analyzedAt: Date?

    init(analyses: [PlaylistLibraryAnalysis]) {
        var order: [String] = []
        var drafts: [String: Draft] = [:]

        for analysis in analyses.sorted(by: { $0.playlistName < $1.playlistName }) {
            for track in analysis.tracks {
                let key = Self.key(for: track.seed)
                let availability = LibraryInventoryAvailability(track.disposition)
                if var draft = drafts[key] {
                    draft.absorb(track: track, availability: availability, playlistName: analysis.playlistName)
                    drafts[key] = draft
                } else {
                    order.append(key)
                    drafts[key] = Draft(
                        key: key,
                        track: track,
                        availability: availability,
                        playlistName: analysis.playlistName
                    )
                }
            }
        }

        self.entries = order.compactMap { drafts[$0]?.entry }
        self.playlistCount = analyses.count
        self.analyzedAt = analyses.map(\.analyzedAt).max()
    }

    func counts() -> [LibraryInventoryAvailability: Int] {
        entries.reduce(into: [:]) { result, entry in
            result[entry.availability, default: 0] += 1
        }
    }

    /// Tracks the user already owns, whether or not a playlist can link them.
    var alreadyOwnedCount: Int {
        entries.lazy.filter { $0.availability == .referenced || $0.availability == .belowTarget || $0.availability == .downloaded }.count
    }

    func filtered(availability: LibraryInventoryAvailability?, query: String) -> [LibraryInventoryEntry] {
        entries
            .filter { availability == nil || $0.availability == availability }
            .filter { $0.matches(query) }
            .sorted { lhs, rhs in
                if lhs.availability.sortPriority != rhs.availability.sortPriority {
                    return lhs.availability.sortPriority < rhs.availability.sortPriority
                }
                if lhs.artist.localizedCaseInsensitiveCompare(rhs.artist) != .orderedSame {
                    return lhs.artist.localizedCaseInsensitiveCompare(rhs.artist) == .orderedAscending
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private static func key(for seed: PlaylistTrackSeed) -> String {
        let artist = seed.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let title = seed.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(artist)\u{1F}\(title)"
    }

    private struct Draft {
        var entry: LibraryInventoryEntry

        init(
            key: String,
            track: PlaylistTrackRecord,
            availability: LibraryInventoryAvailability,
            playlistName: String
        ) {
            entry = LibraryInventoryEntry(
                id: key,
                artist: track.seed.artist,
                title: track.seed.title,
                album: track.seed.album,
                lengthSeconds: track.seed.lengthSeconds,
                availability: availability,
                localPath: track.localPath,
                quality: track.quality,
                playlistNames: [playlistName],
                variesByPlaylist: false
            )
        }

        mutating func absorb(
            track: PlaylistTrackRecord,
            availability: LibraryInventoryAvailability,
            playlistName: String
        ) {
            if !entry.playlistNames.contains(playlistName) {
                entry.playlistNames.append(playlistName)
            }
            if availability != entry.availability {
                entry.variesByPlaylist = true
            }
            guard availability.rank < entry.availability.rank else {
                entry.album = entry.album ?? track.seed.album
                entry.localPath = entry.localPath ?? track.localPath
                entry.quality = entry.quality ?? track.quality
                return
            }
            entry.availability = availability
            entry.localPath = track.localPath ?? entry.localPath
            entry.quality = track.quality ?? entry.quality
            entry.album = track.seed.album ?? entry.album
            entry.lengthSeconds = track.seed.lengthSeconds ?? entry.lengthSeconds
        }
    }
}
