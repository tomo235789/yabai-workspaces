import Foundation

/// Result of running an external process.
public struct CommandResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { exitCode == 0 }
}

public enum CommandError: Error, CustomStringConvertible {
    case launchFailed(command: String, underlying: Error)
    case nonZeroExit(command: String, result: CommandResult)

    public var description: String {
        switch self {
        case let .launchFailed(command, underlying):
            return "failed to launch `\(command)`: \(underlying)"
        case let .nonZeroExit(command, result):
            let detail = result.stderr.isEmpty ? result.stdout : result.stderr
            return "`\(command)` exited \(result.exitCode): \(detail.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

/// The single seam between YWRCore and the outside world. Everything that
/// shells out (yabai, `open`, `which`) goes through this so the whole core can
/// be unit tested against an in-memory fake — the Dependency Inversion boundary.
public protocol CommandRunner: Sendable {
    /// Runs `executable` with `arguments`, returning captured output.
    /// Does not throw on non-zero exit; inspect `CommandResult.exitCode`.
    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult
}

public extension CommandRunner {
    /// Convenience that throws on non-zero exit and returns trimmed stdout.
    func output(_ executable: String, _ arguments: [String]) throws -> String {
        let result = try run(executable, arguments)
        guard result.succeeded else {
            throw CommandError.nonZeroExit(command: ([executable] + arguments).joined(separator: " "), result: result)
        }
        return result.stdout
    }
}

/// Production `CommandRunner` backed by `Foundation.Process`.
public struct ProcessCommandRunner: CommandRunner {
    public init() {}

    public func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        let process = Process()
        // Resolve bare command names via `/usr/bin/env` so callers don't hardcode paths.
        if executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed(command: executable, underlying: error)
        }

        // Read before waitUntilExit to avoid deadlock on large output.
        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
}
