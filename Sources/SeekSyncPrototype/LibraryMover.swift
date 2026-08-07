import Foundation

enum LibraryMoveError: LocalizedError, Equatable {
    case destinationInsideLibrary
    case conflicts([String])

    var errorDescription: String? {
        switch self {
        case .destinationInsideLibrary:
            return "Choose a folder outside the current downloads folder."
        case .conflicts(let names):
            let preview = names.prefix(3).joined(separator: ", ")
            let suffix = names.count > 3 ? " and \(names.count - 3) more" : ""
            return "The new folder already contains \(preview)\(suffix). Nothing was moved."
        }
    }
}

struct LibraryMoveResult: Equatable {
    let movedItemCount: Int
}

struct LibraryMover {
    let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func moveContents(from source: URL, to destination: URL) throws -> LibraryMoveResult {
        let source = source.standardizedFileURL
        let destination = destination.standardizedFileURL
        guard source != destination else { return LibraryMoveResult(movedItemCount: 0) }
        guard !destination.path.hasPrefix(source.path + "/") else {
            throw LibraryMoveError.destinationInsideLibrary
        }

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        guard fileManager.fileExists(atPath: source.path) else {
            return LibraryMoveResult(movedItemCount: 0)
        }

        let items = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil,
            options: []
        )
        let conflicts = items
            .map(\.lastPathComponent)
            .filter { fileManager.fileExists(atPath: destination.appendingPathComponent($0).path) }
            .sorted()
        guard conflicts.isEmpty else { throw LibraryMoveError.conflicts(conflicts) }

        for item in items {
            try fileManager.moveItem(
                at: item,
                to: destination.appendingPathComponent(item.lastPathComponent)
            )
        }
        return LibraryMoveResult(movedItemCount: items.count)
    }
}
