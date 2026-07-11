import Foundation

/// A minimal logging sink. Abstracted so the daemon/handler can be tested by
/// capturing messages instead of writing to the console (Dependency Inversion).
public protocol EventLogging: Sendable {
    func log(_ message: String)
}

/// Prints timestamped lines to stdout — used by the long-running daemon.
public struct ConsoleLogger: EventLogging {
    public init() {}

    public func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        print("[\(stamp)] \(message)")
    }
}
