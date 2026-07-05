import Foundation

struct CommandResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum CommandRunnerError: LocalizedError, Sendable {
    case nonZeroExit(args: [String], stderr: String, stdout: String, exitCode: Int32)
    case timeout(args: [String])

    var errorDescription: String? {
        switch self {
        case let .nonZeroExit(args, stderr, stdout, exitCode):
            let message = stderr.isEmpty ? stdout : stderr
            return "container \(args.joined(separator: " ")) failed (\(exitCode)): \(message)"
        case let .timeout(args):
            return "container \(args.joined(separator: " ")) timed out"
        }
    }
}

enum CommandRunner {
    static let containerPath = "/usr/local/bin/container"

    static var isCLIInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: containerPath)
    }

    static func run(_ args: [String], timeout: TimeInterval = 20) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: containerPath)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Drain pipes concurrently: waiting for exit before reading deadlocks
        // once output exceeds the 64KB pipe buffer (large `ls`/`inspect` JSON).
        var stdoutData = Data()
        var stderrData = Data()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw CommandRunnerError.timeout(args: args)
        }
        readers.wait()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let result = CommandResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)

        guard result.exitCode == 0 else {
            throw CommandRunnerError.nonZeroExit(
                args: args,
                stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines),
                stdout: stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                exitCode: result.exitCode
            )
        }

        return result
    }
}
