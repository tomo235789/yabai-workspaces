import Foundation

/// Launches applications and waits for their windows to appear. Abstracted so
/// restore can be tested without actually spawning apps or sleeping.
public protocol AppLaunching: Sendable {
    /// True if `appName` already has at least one window in `windows`.
    func isRunning(_ appName: String, windows: [Window]) -> Bool

    /// Launches `appName` via `open -a`. Throws if the launch command fails.
    func launch(_ appName: String) throws
}

/// A clock/sleep seam so retry loops don't wall-clock sleep in tests.
public protocol Waiter: Sendable {
    func wait(seconds: Double)
}

public struct RealWaiter: Waiter {
    public init() {}
    public func wait(seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }
}

public struct AppLauncher: AppLaunching {
    private let runner: CommandRunner

    public init(runner: CommandRunner) {
        self.runner = runner
    }

    public func isRunning(_ appName: String, windows: [Window]) -> Bool {
        windows.contains { $0.app == appName }
    }

    public func launch(_ appName: String) throws {
        let result = try runner.run("open", ["-a", appName])
        guard result.succeeded else {
            throw CommandError.nonZeroExit(command: "open -a \(appName)", result: result)
        }
    }
}
