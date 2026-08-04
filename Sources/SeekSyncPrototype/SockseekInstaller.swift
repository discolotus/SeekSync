import CryptoKit
import Foundation

enum SockseekInstallError: LocalizedError {
    case unsupportedArchitecture
    case invalidDownload
    case checksumMismatch
    case extractionFailed(String)
    case binaryMissing

    var errorDescription: String? {
        switch self {
        case .unsupportedArchitecture:
            return "This Mac architecture does not have a supported Sockseek release."
        case .invalidDownload:
            return "Sockseek returned an invalid download response."
        case .checksumMismatch:
            return "Sockseek's download did not match its published SHA-256 digest."
        case .extractionFailed(let detail):
            return "Sockseek could not be unpacked: \(detail)"
        case .binaryMissing:
            return "The Sockseek archive did not contain its executable."
        }
    }
}

struct SockseekRelease: Equatable {
    let version: String
    let archiveURL: URL
    let sha256: String

    static var current: SockseekRelease? {
#if arch(arm64)
        return SockseekRelease(
            version: "3.0.4",
            archiveURL: URL(string: "https://github.com/fiso64/sockseek/releases/download/v3.0.4/sockseek_3.0.4_osx-arm64.tar.gz")!,
            sha256: "584bb1e749a48fd862f34893bcc93220a9663bb87976cf98c9cb05b7c3783469"
        )
#elseif arch(x86_64)
        return SockseekRelease(
            version: "3.0.4",
            archiveURL: URL(string: "https://github.com/fiso64/sockseek/releases/download/v3.0.4/sockseek_3.0.4_osx-x64.tar.gz")!,
            sha256: "6dae9dc60f0521e6ec6e37191b171e3808c5ea6fd112756fd5c4d57d04531c60"
        )
#else
        return nil
#endif
    }
}

struct SockseekInstaller {
    let fileManager: FileManager
    let session: URLSession

    init(fileManager: FileManager = .default, session: URLSession = .shared) {
        self.fileManager = fileManager
        self.session = session
    }

    static func managedBinaryURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SeekSyncPrototype/Tools/sockseek", isDirectory: true)
    }

    func install(release: SockseekRelease? = .current) async throws -> URL {
        guard let release else { throw SockseekInstallError.unsupportedArchitecture }
        let (archiveData, response) = try await session.data(from: release.archiveURL)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              !archiveData.isEmpty else {
            throw SockseekInstallError.invalidDownload
        }
        let digest = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
        guard digest == release.sha256 else { throw SockseekInstallError.checksumMismatch }

        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("SeekSync-Sockseek-\(UUID().uuidString)", isDirectory: true)
        let archiveURL = temporaryRoot.appendingPathComponent("sockseek.tar.gz")
        let extractionURL = temporaryRoot.appendingPathComponent("extracted", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }
        try fileManager.createDirectory(at: extractionURL, withIntermediateDirectories: true)
        try archiveData.write(to: archiveURL, options: .atomic)
        try await extract(archiveURL: archiveURL, into: extractionURL)

        guard let extractedBinary = findBinary(in: extractionURL) else {
            throw SockseekInstallError.binaryMissing
        }
        let destination = Self.managedBinaryURL(fileManager: fileManager)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stagedDestination = destination.deletingLastPathComponent().appendingPathComponent(".sockseek-\(UUID().uuidString)")
        try fileManager.copyItem(at: extractedBinary, to: stagedDestination)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagedDestination.path)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: stagedDestination)
        } else {
            try fileManager.moveItem(at: stagedDestination, to: destination)
        }
        return destination
    }

    private func extract(archiveURL: URL, into destination: URL) async throws {
        let result = try await Task.detached {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xzf", archiveURL.path, "-C", destination.path]
            process.standardOutput = output
            process.standardError = output
            try process.run()
            process.waitUntilExit()
            let detail = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return (process.terminationStatus, detail)
        }.value
        guard result.0 == 0 else {
            throw SockseekInstallError.extractionFailed(result.1.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func findBinary(in directory: URL) -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == "sockseek" {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { return url }
        }
        return nil
    }
}
