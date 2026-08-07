import CryptoKit
import Foundation

/// A cheap fingerprint of the music library folder taken while a preview ran.
///
/// Sockseek rebuilds its music-directory index on every preview pass, reading
/// tags from every file in the library. Walking the same tree without opening
/// the files costs a fraction of that, so the stamp is an affordable way to
/// notice added, removed, or rewritten files before a cached index is reused.
struct LibraryScanStamp: Codable, Hashable {
    var fileCount: Int
    var newestModification: Date
    var totalSize: Int64

    static func make(libraryPath: String, fileManager: FileManager = .default) -> LibraryScanStamp? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: libraryPath),
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var fileCount = 0
        var newest = Date.distantPast
        var totalSize: Int64 = 0
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            fileCount += 1
            totalSize += Int64(values.fileSize ?? 0)
            if let modified = values.contentModificationDate, modified > newest {
                newest = modified
            }
        }
        return LibraryScanStamp(fileCount: fileCount, newestModification: newest, totalSize: totalSize)
    }
}

/// Stores the Sockseek index produced by a read-only preview so the next
/// preview of the same playlist can skip the library tag scan.
///
/// A cached entry is only reused when the preview target (library folder,
/// preferred conditions) and the library contents are unchanged, so a hit
/// cannot mask a file the user added or replaced since the last run.
struct LibraryPreviewIndexCache {
    struct Key: Hashable {
        var playlistID: String
        var libraryPath: String
        var preferredFormat: String
        var minimumBitrateKbps: Int?
        var conditionFingerprint: String

        fileprivate var identity: String {
            let canonical = [
                playlistID,
                libraryPath,
                preferredFormat.lowercased(),
                minimumBitrateKbps.map(String.init) ?? "",
                conditionFingerprint
            ].joined(separator: "\u{1F}")
            return SHA256.hash(data: Data(canonical.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
        }
    }

    struct Snapshot: Hashable {
        var gated: [SockseekIndexEntry]
        var ungated: [SockseekIndexEntry]
    }

    /// A cached index only saves work while it still describes the library, and
    /// a stale file left behind by a folder the user abandoned should not live
    /// forever.
    static let maximumAge: TimeInterval = 60 * 60 * 24 * 30

    private static let version = 1

    private let fileManager: FileManager
    private let directory: URL

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else if let override = ProcessInfo.processInfo.environment["SEEKSYNC_PREVIEW_INDEX_CACHE_DIR"],
                  !override.isEmpty {
            self.directory = URL(fileURLWithPath: NSString(string: override).expandingTildeInPath, isDirectory: true)
        } else {
            self.directory = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/SeekSync/PreviewIndexes", isDirectory: true)
        }
    }

    func load(key: Key, stamp: LibraryScanStamp, now: Date = Date()) -> Snapshot? {
        let url = url(for: key)
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.version == Self.version,
              record.key == key.identity,
              record.stamp == stamp,
              now.timeIntervalSince(record.updatedAt) <= Self.maximumAge else {
            return nil
        }
        let gated = surviving(record.gated)
        let ungated = surviving(record.ungated)
        guard !gated.isEmpty || !ungated.isEmpty else { return nil }
        return Snapshot(gated: gated, ungated: ungated)
    }

    func store(key: Key, stamp: LibraryScanStamp, snapshot: Snapshot, now: Date = Date()) {
        let record = Record(
            version: Self.version,
            key: key.identity,
            stamp: stamp,
            updatedAt: now,
            gated: snapshot.gated,
            ungated: snapshot.ungated
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        let url = url(for: key)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Drops rows whose file disappeared since the preview that produced them.
    /// Unresolved rows are kept: they record that a track had no local match,
    /// which the stamp check already ties to an unchanged library.
    private func surviving(_ entries: [SockseekIndexEntry]) -> [SockseekIndexEntry] {
        entries.filter { entry in
            guard entry.isAvailable, let path = entry.path else { return true }
            return fileManager.fileExists(atPath: path)
        }
    }

    private func url(for key: Key) -> URL {
        directory.appendingPathComponent("\(key.identity).json")
    }

    private struct Record: Codable {
        var version: Int
        var key: String
        var stamp: LibraryScanStamp
        var updatedAt: Date
        var gated: [SockseekIndexEntry]
        var ungated: [SockseekIndexEntry]
    }
}
