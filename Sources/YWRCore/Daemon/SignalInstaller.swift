import Foundation

// Implemented via ollama gemma4:31b, reviewed and integrated unchanged.
// Registers yabai signals so yabai itself runs `ywr restore --auto` on display
// changes — an event-driven alternative to the polling daemon.

public struct SignalDefinition: Equatable, Sendable {
    public let event: String
    public let label: String

    public init(event: String, label: String) {
        self.event = event
        self.label = label
    }
}

public enum SignalError: Error, CustomStringConvertible {
    case installFailed(event: String, detail: String)
    case removeFailed(label: String, detail: String)

    public var description: String {
        switch self {
        case .installFailed(let event, let detail):
            return "Failed to install yabai signal for event '\(event)': \(detail)"
        case .removeFailed(let label, let detail):
            return "Failed to remove yabai signal '\(label)': \(detail)"
        }
    }
}

public struct SignalInstaller: Sendable {
    private let runner: CommandRunner
    private let executable: String
    private let ywrInvocation: String

    public init(runner: CommandRunner, ywrInvocation: String, executable: String = "yabai") {
        self.runner = runner
        self.ywrInvocation = ywrInvocation
        self.executable = executable
    }

    public var definitions: [SignalDefinition] {
        ["display_added", "display_removed", "display_moved"].map { event in
            SignalDefinition(event: event, label: "ywr_\(event)")
        }
    }

    /// Installs all signals. If any `--add` fails, the signals already added are
    /// rolled back before the error is rethrown, so install is all-or-nothing.
    public func install() throws {
        var added: [String] = []
        for def in definitions {
            let args = [
                "-m",
                "signal",
                "--add",
                "event=\(def.event)",
                "action=\(ywrInvocation)",
                "label=\(def.label)"
            ]
            let result = try runner.run(executable, args)
            if !result.succeeded {
                for label in added {
                    _ = try? runner.run(executable, ["-m", "signal", "--remove", label])
                }
                throw SignalError.installFailed(
                    event: def.event,
                    detail: result.stderr.isEmpty ? result.stdout : result.stderr
                )
            }
            added.append(def.label)
        }
    }

    /// Removes all ywr signals, returning any failures instead of discarding
    /// them so the caller can report leftover registrations.
    @discardableResult
    public func uninstall() -> [SignalError] {
        var errors: [SignalError] = []
        for def in definitions {
            let args = ["-m", "signal", "--remove", def.label]
            do {
                let result = try runner.run(executable, args)
                if !result.succeeded {
                    errors.append(.removeFailed(label: def.label, detail: result.stderr.isEmpty ? result.stdout : result.stderr))
                }
            } catch {
                errors.append(.removeFailed(label: def.label, detail: "\(error)"))
            }
        }
        return errors
    }

    public func installedLabels() -> [String] {
        definitions.map { $0.label }
    }
}
