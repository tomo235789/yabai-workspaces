import Foundation

/// A runnable CLI verb. Each command owns its dependencies (injected at
/// construction by the composition root in `main`), so adding a command never
/// requires editing the dispatcher — Open/Closed.
protocol Command {
    var name: String { get }
    var summary: String { get }
    var usage: String { get }
    /// Runs with the arguments *after* the command name. Returns a process exit code.
    func run(_ args: [String]) throws -> Int32
}

extension Command {
    var usage: String {
        "ywr \(name)"
    }
}

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case message(String)

    var description: String {
        switch self {
        case let .usage(text): text
        case let .message(text): text
        }
    }
}
