import Foundation

/// Orchestrates a restore: plan -> launch missing apps -> re-match -> apply
/// geometry -> report. Every collaborator is an injected abstraction, so the
/// whole flow is unit-testable without touching a real machine.
public struct SnapshotRestorer: Sendable {
    private let yabai: YabaiQuerying & YabaiControlling
    private let launcher: AppLaunching
    private let planner: RestorePlanner
    private let windowMatcher: WindowMatching
    private let displayMatcher: DisplayMatching
    private let provisioner: SpaceProvisioner
    private let waiter: Waiter
    private let launchRetries: Int
    private let launchWaitSeconds: Double

    public init(
        yabai: YabaiQuerying & YabaiControlling,
        launcher: AppLaunching,
        planner: RestorePlanner = RestorePlanner(),
        windowMatcher: WindowMatching = WindowMatcher(),
        displayMatcher: DisplayMatching = DisplayMatcher(),
        provisioner: SpaceProvisioner = SpaceProvisioner(),
        waiter: Waiter = RealWaiter(),
        launchRetries: Int = 10,
        launchWaitSeconds: Double = 0.5
    ) {
        self.yabai = yabai
        self.launcher = launcher
        self.planner = planner
        self.windowMatcher = windowMatcher
        self.displayMatcher = displayMatcher
        self.provisioner = provisioner
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

    /// Computes the missing labeled Spaces that `restore(createSpaces:)` would
    /// create. Pure — backs `--dry-run --create-spaces`.
    public func provisionRequests(for snapshot: Snapshot) throws -> [SpaceProvisionRequest] {
        let currentDisplays = try yabai.queryDisplays()
        let currentSpaces = try yabai.querySpaces()
        let displayMap = displayIndexMap(saved: snapshot.displayProfile.displays, current: currentDisplays)
        return provisioner.requests(savedSpaces: snapshot.spaces, currentSpaces: currentSpaces, displayMap: displayMap)
    }

    /// Executes the restore and returns a report of every window's outcome.
    /// When `createSpaces` is true, missing labeled Spaces are created first so
    /// windows can be moved to Spaces that don't exist yet.
    public func restore(_ snapshot: Snapshot, createSpaces: Bool = false) throws -> RestoreReport {
        // Provision missing Spaces BEFORE planning, so the plan maps windows to
        // the freshly-created (now labeled) Spaces rather than a fallback.
        if createSpaces {
            try provisionSpaces(for: snapshot)
        }

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

        // 5. Restore focus to the window that had it at capture time (best
        // effort, done last so it isn't stolen by subsequent moves).
        if let focusedStep = plan.steps.first(where: { $0.saved.focused }),
           let id = focusedStep.matchedWindowId {
            try? yabai.focusWindow(id)
        }
        return report
    }

    // MARK: - Space provisioning

    private func displayIndexMap(saved: [Display], current: [Display]) -> [Int: Int] {
        var map: [Int: Int] = [:]
        // Only confident correspondences steer provisioning; a weak match could
        // otherwise create a Space on the wrong monitor. The saved.display
        // fallback in SpaceProvisioner covers the rest.
        for c in displayMatcher.match(saved: saved, current: current) where c.isConfident {
            map[saved[c.savedIndex].index] = c.currentDisplayIndex
        }
        return map
    }

    private func provisionSpaces(for snapshot: Snapshot) throws {
        let requests = try provisionRequests(for: snapshot)
        for request in requests {
            // Best-effort per request: one bad createSpace/label must not abort
            // the whole restore (matches apply(_:) / space-label resilience).
            do {
                try yabai.createSpace(onDisplay: request.displayIndex)
                // The just-created space is the newest unlabeled one on that display.
                let spaces = try yabai.querySpaces()
                if let target = spaces
                    .filter({ $0.display == request.displayIndex && $0.label.isEmpty })
                    .max(by: { $0.index < $1.index }) {
                    try yabai.labelSpace(index: target.index, label: request.label)
                }
            } catch {
                continue
            }
        }
    }

    // MARK: - Execution

    private func apply(_ step: WindowRestoreStep) -> RestoreOutcome {
        guard let id = step.matchedWindowId else {
            return RestoreOutcome(label: step.describedLabel, status: .launchedAndDeferred)
        }
        let flags = step.saved.flags
        do {
            // Clear any live minimized/fullscreen state FIRST — yabai cannot move
            // or resize a window while it is minimized or native-fullscreen, so
            // geometry commands would otherwise fail before the state is cleared.
            // (setMinimized/setFullscreen are no-ops when already in the state.)
            try yabai.setMinimized(id, false)
            try yabai.setFullscreen(id, false)

            try yabai.moveWindow(id, toDisplay: step.targetDisplayIndex)
            try yabai.moveWindow(id, toSpace: step.targetSpaceIndex)
            try yabai.setFloating(id, step.shouldFloat)
            if step.shouldFloat && !flags.fullscreen {
                // move/resize only apply meaningfully to floating, non-fullscreen windows.
                try yabai.moveWindow(id, toX: step.targetFrame.x, y: step.targetFrame.y)
                try yabai.resizeWindow(id, toW: step.targetFrame.w, h: step.targetFrame.h)
            }
            // Apply the saved blocking states last so the moves above can run.
            try yabai.setFullscreen(id, flags.fullscreen)
            try yabai.setMinimized(id, flags.minimized)
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
