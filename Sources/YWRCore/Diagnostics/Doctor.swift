import Foundation

public enum CheckStatus: Sendable, Equatable {
    case pass
    case warn
    case fail
}

public struct CheckResult: Sendable {
    public let name: String
    public let status: CheckStatus
    public let message: String

    public init(name: String, status: CheckStatus, message: String) {
        self.name = name
        self.status = status
        self.message = message
    }
}

/// A single environment check. New checks are added by conforming a new type —
/// the runner never changes (Open/Closed).
public protocol DiagnosticCheck: Sendable {
    var name: String { get }
    func run() -> CheckResult
}

/// Verifies the `yabai` binary is on PATH.
public struct YabaiInstalledCheck: DiagnosticCheck {
    public let name = "yabai installed"
    private let runner: CommandRunner
    private let executable: String

    public init(runner: CommandRunner, executable: String = "yabai") {
        self.runner = runner
        self.executable = executable
    }

    public func run() -> CheckResult {
        do {
            let result = try runner.run("which", [executable])
            if result.succeeded {
                return CheckResult(name: name, status: .pass,
                                   message: "found at \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            return CheckResult(name: name, status: .fail,
                               message: "`\(executable)` not found on PATH. Install via `brew install koekeishiya/formulae/yabai`.")
        } catch {
            return CheckResult(name: name, status: .fail, message: "could not check: \(error)")
        }
    }
}

/// Verifies yabai actually answers a displays query (i.e. it's running and the
/// scripting addition/permissions are functional enough to read state).
public struct YabaiQueryableCheck: DiagnosticCheck {
    public let name = "yabai query --displays"
    private let yabai: YabaiQuerying

    public init(yabai: YabaiQuerying) {
        self.yabai = yabai
    }

    public func run() -> CheckResult {
        do {
            let displays = try yabai.queryDisplays()
            return CheckResult(name: name, status: .pass,
                               message: "responded with \(displays.count) display(s)")
        } catch {
            return CheckResult(name: name, status: .fail,
                               message: "query failed — is the yabai service running? (`yabai --start-service`). \(error)")
        }
    }
}

/// A static advisory about macOS setup the tool can't verify programmatically.
public struct MacOSSettingsNoticeCheck: DiagnosticCheck {
    public let name = "macOS settings"

    public init() {}

    public func run() -> CheckResult {
        CheckResult(
            name: name,
            status: .warn,
            message: "ywr supports both values of 'Displays have separate Spaces'. With it OFF, restore may visibly visit virtual desktops to discover their windows. Accessibility permission and the yabai scripting-addition are still required for cross-Space moves; otherwise ywr falls back to positions-only."
        )
    }
}

public struct DoctorReport: Sendable {
    public let results: [CheckResult]

    public init(results: [CheckResult]) {
        self.results = results
    }

    /// Non-zero exit is warranted only when a hard check fails.
    public var hasFailure: Bool { results.contains { $0.status == .fail } }
}

/// Runs an ordered list of checks. The list is injected, so composition (which
/// checks, in what order) is a caller decision.
public struct Doctor: Sendable {
    private let checks: [DiagnosticCheck]

    public init(checks: [DiagnosticCheck]) {
        self.checks = checks
    }

    public func run() -> DoctorReport {
        DoctorReport(results: checks.map { $0.run() })
    }
}
