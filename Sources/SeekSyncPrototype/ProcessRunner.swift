import Foundation

struct ProcessResult {
    let exitCode: Int32
    let output: String
}

struct SockseekProcessRunner {
    func run(
        _ command: SLDLCommand,
        onOutput: (@Sendable (String) async -> Void)? = nil
    ) async throws -> ProcessResult {
        let processBox = RunningProcessBox()
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("seeksync-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        let worker = Task.detached(priority: .userInitiated) {
            defer { processBox.markFinished() }
                try Task.checkCancellation()
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command.executable)
                process.arguments = command.arguments
                var environment = ProcessInfo.processInfo.environment
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                environment["PATH"] = [
                    "\(home)/.local/bin",
                    "/opt/homebrew/bin",
                    "/usr/local/bin",
                    "/usr/bin",
                    "/bin",
                    "/usr/sbin",
                    "/sbin"
                ].joined(separator: ":")
                process.environment = environment

                let outputHandle = try FileHandle(forWritingTo: temporaryURL)
                process.standardOutput = outputHandle
                process.standardError = outputHandle

                defer {
                    try? outputHandle.close()
                }

                try processBox.start(process)
                process.waitUntilExit()
                try Task.checkCancellation()
                try outputHandle.synchronize()
                return process.terminationStatus
        }
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        return try await withTaskCancellationHandler {
            var emittedByteCount = 0
            while !processBox.isFinished {
                try Task.checkCancellation()
                emittedByteCount = await emitNewOutput(
                    from: temporaryURL,
                    after: emittedByteCount,
                    final: false,
                    callback: onOutput
                )
                try await Task.sleep(nanoseconds: 80_000_000)
            }

            let exitCode = try await worker.value
            _ = await emitNewOutput(
                from: temporaryURL,
                after: emittedByteCount,
                final: true,
                callback: onOutput
            )
            let data = try Data(contentsOf: temporaryURL)
            return ProcessResult(exitCode: exitCode, output: String(decoding: data, as: UTF8.self))
        } onCancel: {
            worker.cancel()
            processBox.terminate()
        }
    }

    private func emitNewOutput(
        from url: URL,
        after emittedByteCount: Int,
        final: Bool,
        callback: (@Sendable (String) async -> Void)?
    ) async -> Int {
        guard let callback,
              let data = try? Data(contentsOf: url),
              data.count > emittedByteCount else { return emittedByteCount }

        let endIndex: Int
        if final {
            endIndex = data.count
        } else if let newline = data[emittedByteCount...].lastIndex(of: 0x0A) {
            endIndex = data.distance(from: data.startIndex, to: data.index(after: newline))
        } else {
            return emittedByteCount
        }

        let chunk = String(decoding: data[emittedByteCount..<endIndex], as: UTF8.self)
        await callback(chunk)
        return endIndex
    }

    func version(at binaryPath: String) async -> DependencyState {
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else { return .missing }
        let command = SLDLCommand(executable: binaryPath, arguments: ["--version"])
        do {
            let result = try await run(command)
            let version = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.exitCode == 0, version.first == "3" else {
                return .failed("Sockseek 3 required")
            }
            return .ready(version: version)
        } catch {
            return .failed("Sockseek check failed")
        }
    }
}

private final class RunningProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    private var cancelled = false
    private var finished = false

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    func start(_ process: Process) throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        self.process = process
        try process.run()
    }

    func terminate() {
        lock.lock()
        cancelled = true
        let running = process
        lock.unlock()
        if running?.isRunning == true { running?.terminate() }
    }

    func markFinished() {
        lock.lock()
        finished = true
        lock.unlock()
    }
}
