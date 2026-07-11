import Foundation

/// A single window's intended restoration, expressed against the *current*
/// configuration (target frame already projected onto the live display).
public struct WindowRestoreStep: Sendable, Equatable {
    public let saved: WindowSnapshot
    /// The live window id if already matched; nil means the app must be
    /// launched (or the window re-matched) before this step can run.
    public var matchedWindowId: Int?
    public let targetDisplayIndex: Int
    public let targetSpaceIndex: Int
    public let targetFrame: Frame
    public let shouldFloat: Bool

    public init(
        saved: WindowSnapshot,
        matchedWindowId: Int?,
        targetDisplayIndex: Int,
        targetSpaceIndex: Int,
        targetFrame: Frame,
        shouldFloat: Bool
    ) {
        self.saved = saved
        self.matchedWindowId = matchedWindowId
        self.targetDisplayIndex = targetDisplayIndex
        self.targetSpaceIndex = targetSpaceIndex
        self.targetFrame = targetFrame
        self.shouldFloat = shouldFloat
    }

    public var describedLabel: String {
        let title = saved.title.isEmpty ? "(untitled)" : saved.title
        return "\(saved.app) — \(title)"
    }
}

/// The full, inspectable restore plan. `restore --dry-run` prints this without
/// executing; the executor consumes it. Separating plan from execution keeps
/// the decision logic pure and testable.
public struct RestorePlan: Sendable {
    public var steps: [WindowRestoreStep]
    /// Apps that need launching before their windows can be matched.
    public var appsToLaunch: [String]
    /// Space labels to (re)apply: display index -> [spaceIndex: label].
    public var spaceLabels: [(spaceIndex: Int, label: String)]
    /// Saved windows with no current match and no launchable app resolution.
    public var unmatched: [WindowSnapshot]

    public init(
        steps: [WindowRestoreStep] = [],
        appsToLaunch: [String] = [],
        spaceLabels: [(spaceIndex: Int, label: String)] = [],
        unmatched: [WindowSnapshot] = []
    ) {
        self.steps = steps
        self.appsToLaunch = appsToLaunch
        self.spaceLabels = spaceLabels
        self.unmatched = unmatched
    }
}

/// Outcome of one attempted step, collected into the end-of-run report so no
/// failure is ever swallowed silently (a P0 requirement).
public struct RestoreOutcome: Sendable {
    public enum Status: Sendable, Equatable {
        case moved
        case launchedAndDeferred
        case failed(reason: String)
        case unmatched
    }

    public let label: String
    public let status: Status

    public init(label: String, status: Status) {
        self.label = label
        self.status = status
    }
}

public struct RestoreReport: Sendable {
    public var outcomes: [RestoreOutcome]

    public init(outcomes: [RestoreOutcome] = []) {
        self.outcomes = outcomes
    }

    public var moved: [RestoreOutcome] { outcomes.filter { $0.status == .moved } }
    public var failures: [RestoreOutcome] {
        outcomes.filter {
            if case .failed = $0.status { return true }
            return $0.status == .unmatched
        }
    }
}
