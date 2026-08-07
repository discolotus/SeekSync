import Foundation

// Writes one combined rekordbox library describing every synced playlist, so a
// single File → Import Library brings the whole downloads folder into
// rekordbox with its playlist tree intact. SeekSync only ever writes its own
// file here; it never reads or edits a rekordbox library.
//
// BPM, key, and cue points are deliberately absent. Rekordbox analyses tracks
// itself on import and keeps the result in its own database.

struct RekordboxTrack: Equatable {
    var id: Int
    var path: String
    var title: String
    var artist: String
    var album: String
    var lengthSeconds: Int
    var kind: String
}

struct RekordboxPlaylistNode: Equatable {
    var name: String
    var trackIDs: [Int]
}

struct RekordboxCollection: Equatable {
    var tracks: [RekordboxTrack]
    var nodes: [RekordboxPlaylistNode]
}

struct RekordboxCollectionBuilder {
    struct Source {
        var name: String
        var entries: [SockseekIndexEntry]
    }

    func build(from sources: [Source]) -> RekordboxCollection {
        var tracks: [RekordboxTrack] = []
        var idsByPath: [String: Int] = [:]
        var nodes: [RekordboxPlaylistNode] = []

        for source in sources {
            var trackIDs: [Int] = []
            var seen: Set<Int> = []
            for entry in source.entries {
                guard entry.isAvailable, let path = entry.path, !path.isEmpty else { continue }
                let id: Int
                if let existing = idsByPath[path] {
                    id = existing
                } else {
                    id = tracks.count + 1
                    idsByPath[path] = id
                    tracks.append(
                        RekordboxTrack(
                            id: id,
                            path: path,
                            title: entry.title,
                            artist: entry.artist,
                            album: entry.album,
                            lengthSeconds: entry.lengthSeconds,
                            kind: Self.kind(forPath: path)
                        )
                    )
                }
                // A playlist referencing the same file twice would import as a
                // duplicate row in rekordbox.
                if seen.insert(id).inserted { trackIDs.append(id) }
            }
            guard !trackIDs.isEmpty else { continue }
            nodes.append(RekordboxPlaylistNode(name: source.name, trackIDs: trackIDs))
        }

        return RekordboxCollection(tracks: tracks, nodes: nodes)
    }

    static func kind(forPath path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension
        guard !ext.isEmpty else { return "Unknown File" }
        return "\(ext.uppercased()) File"
    }
}

struct RekordboxXMLWriter {
    func xml(for collection: RekordboxCollection) -> String {
        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<DJ_PLAYLISTS Version=\"1.0.0\">",
            "  <PRODUCT Name=\"SeekSync\" Version=\"\(Self.escaped(SeekSyncVersion.shortLabel))\" Company=\"SeekSync\"/>",
            "  <COLLECTION Entries=\"\(collection.tracks.count)\">"
        ]

        for track in collection.tracks {
            var attributes = [
                "TrackID=\"\(track.id)\"",
                "Name=\"\(Self.escaped(track.title))\"",
                "Artist=\"\(Self.escaped(track.artist))\"",
                "Album=\"\(Self.escaped(track.album))\"",
                "Kind=\"\(Self.escaped(track.kind))\""
            ]
            // Sockseek records an unknown length as a negative number, which
            // rekordbox would read as a nonsense running time.
            if track.lengthSeconds > 0 {
                attributes.append("TotalTime=\"\(track.lengthSeconds)\"")
            }
            attributes.append("Location=\"\(Self.escaped(Self.location(forPath: track.path)))\"")
            lines.append("    <TRACK \(attributes.joined(separator: " "))/>")
        }

        lines.append("  </COLLECTION>")
        lines.append("  <PLAYLISTS>")
        lines.append("    <NODE Type=\"0\" Name=\"ROOT\" Count=\"1\">")
        lines.append("      <NODE Type=\"0\" Name=\"SeekSync\" Count=\"\(collection.nodes.count)\">")

        for node in collection.nodes {
            lines.append("        <NODE Type=\"1\" Name=\"\(Self.escaped(node.name))\" KeyType=\"0\" Entries=\"\(node.trackIDs.count)\">")
            for id in node.trackIDs {
                lines.append("          <TRACK Key=\"\(id)\"/>")
            }
            lines.append("        </NODE>")
        }

        lines.append("      </NODE>")
        lines.append("    </NODE>")
        lines.append("  </PLAYLISTS>")
        lines.append("</DJ_PLAYLISTS>")
        return lines.joined(separator: "\n") + "\n"
    }

    static func location(forPath path: String) -> String {
        let absolute = URL(fileURLWithPath: path).absoluteString
        guard absolute.hasPrefix("file://") else { return absolute }
        return "file://localhost" + absolute.dropFirst("file://".count)
    }

    private static func escaped(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.append(character)
            }
        }
        return result
    }
}

struct RekordboxXMLExporter {
    struct Source {
        var name: String
        var indexPath: String
    }

    var fileManager: FileManager = .default
    var parser = SockseekIndexParser()

    static let fileName = "SeekSync.rekordbox.xml"

    /// Demo fixtures never run Sockseek, so they can never have an index to
    /// export. Everything else is offered to `export`, which drops whatever
    /// has not synced yet.
    static func sources(for playlists: [Playlist], outputDirectory: String) -> [Source] {
        let builder = SockseekCommandBuilder()
        return playlists.filter { $0.isFixture != true }.map { playlist in
            Source(
                name: playlist.name,
                indexPath: builder.indexPath(for: playlist, outputDirectory: outputDirectory)
            )
        }
    }

    static func exportURL(outputDirectory: String) -> URL {
        let expanded = NSString(string: outputDirectory).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
            .standardizedFileURL
            .appendingPathComponent(fileName)
    }

    /// Rebuilds the export from the indices currently on disk and returns the
    /// number of tracks written. Returns zero without touching `url` when
    /// there is nothing to export, so a good file is never replaced by an
    /// empty one.
    @discardableResult
    func export(sources: [Source], to url: URL) throws -> Int {
        let builderSources: [RekordboxCollectionBuilder.Source] = sources.compactMap { source in
            let indexURL = URL(fileURLWithPath: NSString(string: source.indexPath).expandingTildeInPath)
            // A playlist that has never synced has no index. Skip it and
            // export the rest rather than failing the whole library.
            guard fileManager.fileExists(atPath: indexURL.path),
                  let entries = try? parser.parse(url: indexURL) else { return nil }
            return .init(name: source.name, entries: entries)
        }

        let collection = RekordboxCollectionBuilder().build(from: builderSources)
        guard !collection.tracks.isEmpty else { return 0 }

        let xml = RekordboxXMLWriter().xml(for: collection)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try xml.write(to: url, atomically: true, encoding: .utf8)
        return collection.tracks.count
    }
}
