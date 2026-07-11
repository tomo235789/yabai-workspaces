import Foundation

/// Orchestrates a restore: plan -> launch missing apps -> re-match -> apply
/// geometry -> report. Every collaborator is an injected abstraction, so the
/// whole flow is unit-testable without touching a real machine.
public struct SnapshotRestorer: Sendable {
    private let yabai: YabaiQuerying & YabaiControlling
    private let launcher: AppLaunching
    private let planner: RestorePlanner
    private let windowMatcher: WindowMatching
    private let waiter: Waiter
    private let launchRetries: Int
    private let launchWaitSeconds: Double

    public init(
        yabai: YabaiQuerying & YabaiControlling,
        launcher: AppLaunching,
        planner: RestorePlanner = RestorePlanner(),
        windowMatcher: WindowMatching = WindowMatcher(),
        waiter: Waiter = RealWaiter(),
        launchRetries: Int = 10,
        launchWaitSeconds: Double = 0.5
    ) {
        self.yabai = yabai
        self.launcher = launcher
        self.planner = planner
        self.windowMatcher = windowMatcher
        self.waiter = waiter
        self.launchRetries = launchRetries
        self.launchWaitSeconds = launchWaitSeconds
    }

    /// Builds a plan without mutating anything — backs `--dry-run`.
    public func buildPlan(for snapshot: Snapshot) throws -> RestorePlan {
        try planner.plan(
            snapshot: snapshot,
            currentDisplays: yabai.queryDisplays(),
            currentSpaces: yabai.querySpaces(),
            currentWindows: yabai.queryWindows()
        )
    }

    /// Executes the restore and returns a report of every window's outcome.
    public func restore(_ snapshot: Snapshot) throws -> RestoreReport {
        var plan = try buildPlan(for: snapshot)
        var report = RestoreReport()

        // 1. Launch missing apps, then wait for their windows to appear.
        for app in plan.appsToLaunch {
            do {
                try launcher.launch(app)
            } catch {
                report.outcomes.append(RestoreOutcome(
                    label: app,
                    status: .failed(reason: "launch failed: \(error)")
                ))
            }
        }
        if !plan.appsToLaunch.isEmpty {
            try waitForApps(plan.appsToLaunch)
            // Re-match deferred steps now that windows may exist.
            plan = try rematchDeferredSteps(in: plan)
        }

        // 2. Re-apply space labels first so subsequent moves land correctly.
        for label in plan.spaceLabels {
            try? yabai.labelSpace(index: label.spaceIndex, label: label.label)
        }

        // 3. Apply each window step.
        for step in plan.steps {
            report.outcomes.append(apply(step))
        }

        // 4. Windows that never matched.
        for saved in plan.unmatched {
            let title = saved.title.isEmpty ? "(untitled)" : saved.title
            report.outcomes.append(RestoreOutcome(
                label: "\(saved.app) — \(title)",
                status: .unmatched
            ))
        }
        return report
    }

    // MARK: - Execution

    private func apply(_ step: WindowRestoreStep) -> RestoreOutcome {
        guard let id = step.matchedWindowId else {
            return RestoreOutcome(label: step.describedLabel, status: .launchedAndDeferred)
        }
        do {
            try yabai.moveWindow(id, toDisplay: step.targetDisplayIndex)
            try yabai.moveWindow(id, toSpace: step.targetSpaceIndex)
            try yabai.setFloating(id, step.shouldFloat)
            if step.shouldFloat {
                // move/resize only apply meaningfully to floating windows.
                try yabai.moveWindow(id, toX: step.targetFrame.x, y: step.targetFrame.y)
                try yabai.resizeWindow(id, toW: step.targetFrame.w, h: step.targetFrame.h)
            }
            return RestoreOutcome(label: step.describedLabel, status: .moved)
        } catch {
            return RestoreOutcome(label: step.describedLabel, status: .failed(reason: "\(error)"))
        }
    }

    private func waitForApps(_ apps: [String]) throws {
        var pending = Set(apps)
        for _ in 0..<launchRetries {
            guard !pending.isEmpty else { break }
            let windows = try yabai.queryWindows()
            pending = pending.filter { !launcher.isRunning($0, windows: windows) }
            if pending.isEmpty { break }
            waiter.wait(seconds: launchWaitSeconds)
        }
    }

    private func rematchDeferredSteps(in plan: RestorePlan) throws -> RestorePlan {
        var updated = plan
        var available = try yabai.queryWindows()
        // Only re-match the deferred (id == nil) steps.
        updated.steps = plan.steps.map { step in
            guard step.matchedWindowId == nil else { return step }
            guard let match = windowMatcher.bestMatch(for: step.saved, among: available) else { return step }
            available.removeAll { $0.id == match.id }
            var resolved = step
            resolved.matchedWindowId = match.id
            return resolved
        }
        return updated
    }
}
