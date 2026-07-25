import Foundation

/// Whether the yabai backend can be used right now. yabai refuses to run when
/// "Displays have separate Spaces" is off, so this decides between the yabai
/// backend and the native (Accessibility) backend at runtime.
public protocol YabaiAvailabilityChecking: Sendable {
    func isAvailable() -> Bool
}

public struct YabaiAvailability: YabaiAvailabilityChecking {
    private let runner: CommandRunner
    private let executable: String

    public init(runner: CommandRunner, executable: String = "yabai") {
        self.runner = runner
        self.executable = executable
    }

    public func isAvailable() -> Bool {
        // A successful displays query means the yabai service is up and answering.
        ((try? runner.run(executable, ["-m", "query", "--displays"]))?.succeeded) ?? false
    }
}

public struct FixedYabaiAvailability: YabaiAvailabilityChecking {
    private let available: Bool
    public init(_ available: Bool) { self.available = available }
    public func isAvailable() -> Bool { available }
}
