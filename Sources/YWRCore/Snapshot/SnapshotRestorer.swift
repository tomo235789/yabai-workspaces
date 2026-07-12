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
    private let desktopWindowDiscovery: VirtualDesktopWindowDiscovering
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
        desktopWindowDiscovery: VirtualDesktopWindowDiscovering? = nil,
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
        self.desktopWindowDiscovery = desktopWindowDiscovery ?? YabaiVirtualDesktopWindowDiscovery(yabai: yabai, waiter: waiter)
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
    ///
    /// With `positionsOnly`, Display/Space moves are skipped entirely and only
    /// each window's geometry is restored on the current Space. Even in the
    /// default mode, a failed Display/Space move (e.g. "Displays have separate
    /// Spaces" off, or no scripting addition) falls back to positions-only for
    /// that window rather than failing it.
    public func restore(_ snapshot: Snapshot, createSpaces: Bool = false, positionsOnly: Bool = false) throws -> RestoreReport {
        // Provision missing Spaces BEFORE planning, so the plan maps windows to
        // the freshly-created (now labeled) Spaces rather than a fallback.
        // Skip when positions-only: we aren't touching Spaces.
        if createSpaces && !positionsOnly {
            try provisionSpaces(for: snapshot)
        }

        var plan: RestorePlan
        if snapshot.spaceMode == .unifiedDesktop {
            plan = planner.plan(snapshot: snapshot,
                                currentDisplays: try yabai.queryDisplays(),
                                currentSpaces: try yabai.querySpaces(),
                                currentWindows: try desktopWindowDiscovery.discover())
        } else {
            plan = try buildPlan(for: snapshot)
        }
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
        // Positions-only must not touch Space configuration at all.
        if !positionsOnly {
            for label in plan.spaceLabels {
                try? yabai.labelSpace(index: label.spaceIndex, label: label.label)
            }
        }

        // 3. Apply each window step. Capture the live display of each window so
        // that when a Display move is skipped/failed, geometry is resolved
        // against the display the window is ACTUALLY on (not the planned one).
        let displayFrameByIndex = Dictionary(
            (try yabai.queryDisplays()).map { ($0.index, $0.frame) },
            uniquingKeysWith: { a, _ in a }
        )
        let windowDisplayById = Dictionary(
            (try yabai.queryWindows()).map { ($0.id, $0.display) },
            uniquingKeysWith: { a, _ in a }
        )
        for step in plan.steps {
            let currentDisplayFrame = step.matchedWindowId
                .flatMap { windowDisplayById[$0] }
                .flatMap { displayFrameByIndex[$0] }
            report.outcomes.append(apply(step, positionsOnly: positionsOnly, currentDisplayFrame: currentDisplayFrame))
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

    // Implemented via ollama gemma4:31b, reviewed and integrated.
    private func apply(_ step: WindowRestoreStep, positionsOnly: Bool, currentDisplayFrame: Frame?) -> RestoreOutcome {
        guard let id = step.matchedWindowId else {
            return RestoreOutcome(label: step.describedLabel, status: .launchedAndDeferred)
        }

        let flags = step.saved.flags
        var degraded = positionsOnly

        do {
            // Full restore temporarily clears blocking states before moving.
            // Positions-only must not change either state because native
            // fullscreen owns a Space and minimize/deminimize is outside its
            // geometry-only contract.
            if !positionsOnly {
                try yabai.setMinimized(id, false)
                try yabai.setFullscreen(id, false)
            }

            if !positionsOnly {
                // Auto-fallback: a Display/Space move can fail when "Displays have
                // separate Spaces" is off or the scripting addition isn't loaded.
                // Degrade to positions-only for this window instead of failing it.
                do {
                    try yabai.moveWindow(id, toDisplay: step.targetDisplayIndex)
                    try yabai.moveWindow(id, toSpace: step.targetSpaceIndex)
                } catch {
                    degraded = true
                }
            }

            try yabai.setFloating(id, step.shouldFloat)

            if step.shouldFloat && !flags.fullscreen {
                // When we didn't move the window to the planned display, resolve
                // its geometry against the display it's actually on so it lands
                // on-screen (and doesn't implicitly cross displays).
                let frame: Frame
                if degraded, let cdf = currentDisplayFrame {
                    frame = step.saved.relativeFrame.resolved(on: cdf)
                } else {
                    frame = step.targetFrame
                }
                try yabai.moveWindow(id, toX: frame.x, y: frame.y)
                try yabai.resizeWindow(id, toW: frame.w, h: frame.h)
            }

            if !positionsOnly {
                try yabai.setFullscreen(id, flags.fullscreen)
                try yabai.setMinimized(id, flags.minimized)
            }

            return RestoreOutcome(label: step.describedLabel, status: degraded ? .movedPositionsOnly : .moved)
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
