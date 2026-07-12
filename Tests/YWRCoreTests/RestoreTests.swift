import XCTest
@testable import YWRCore

final class RestoreTests: XCTestCase {
    private let display = Display(id: 1, uuid: "D1", index: 1, frame: Frame(x: 0, y: 0, w: 1000, h: 1000), spaces: [1, 2])

    private func savedWindow(app: String, title: String, floating: Bool, x: Double, w: Double) -> WindowSnapshot {
        let frame = Frame(x: x, y: 0, w: w, h: 500)
        return WindowSnapshot(
            app: app, title: title, role: "AXWindow", pid: 1, space: 1, display: 1,
            frame: frame,
            relativeFrame: RelativeFrame.within(display.frame, window: frame),
            flags: WindowFlags(floating: floating, sticky: false, minimized: false, fullscreen: false)
        )
    }

    private func makeSnapshot(_ windows: [WindowSnapshot]) -> Snapshot {
        Snapshot(
            name: "test",
            capturedAt: Date(),
            displayProfile: DisplayProfile(fingerprint: "1000x1000", displays: [display]),
            spaces: [SpaceSnapshot(index: 1, label: "code", display: 1)],
            windows: windows
        )
    }

    func testPlannerMatchesRunningWindow() {
        let planner = RestorePlanner()
        let snapshot = makeSnapshot([savedWindow(app: "Code", title: "proj", floating: true, x: 0, w: 500)])
        let live = Window(id: 42, pid: 1, app: "Code", title: "proj", frame: Frame(x: 0, y: 0, w: 500, h: 500), display: 1, space: 1)

        let plan = planner.plan(snapshot: snapshot, currentDisplays: [display],
                                currentSpaces: [Space(id: 1, index: 1, label: "code", display: 1)], currentWindows: [live])
        XCTAssertEqual(plan.steps.count, 1)
        XCTAssertEqual(plan.steps.first?.matchedWindowId, 42)
        XCTAssertTrue(plan.appsToLaunch.isEmpty)
        XCTAssertTrue(plan.unmatched.isEmpty)
    }

    func testPlannerSchedulesLaunchForMissingApp() {
        let planner = RestorePlanner()
        let snapshot = makeSnapshot([savedWindow(app: "Safari", title: "docs", floating: false, x: 0, w: 500)])
        let plan = planner.plan(snapshot: snapshot, currentDisplays: [display],
                                currentSpaces: [Space(id: 1, index: 1, label: "code", display: 1)], currentWindows: [])
        XCTAssertEqual(plan.appsToLaunch, ["Safari"])
        XCTAssertNil(plan.steps.first?.matchedWindowId)
    }

    func testPlannerReportsRunningButUnmatched() {
        let planner = RestorePlanner()
        let live = Window(id: 7, pid: 1, app: "Code", title: "", frame: Frame(x: 0, y: 0, w: 500, h: 500), display: 1, space: 1)
        let snapshot = makeSnapshot([
            savedWindow(app: "Code", title: "proj", floating: false, x: 0, w: 500),
            savedWindow(app: "Code", title: "other", floating: false, x: 500, w: 500)
        ])
        let plan = planner.plan(snapshot: snapshot, currentDisplays: [display], currentSpaces: [], currentWindows: [live])
        XCTAssertEqual(plan.unmatched.count, 1)
    }

    func testRestorerReportsFailuresAndMoves() throws {
        // A genuine geometry failure (setFloating throws) is a real failure;
        // window 42 restores fine.
        let live = Window(id: 42, pid: 1, app: "Code", title: "proj", frame: Frame(x: 0, y: 0, w: 500, h: 500), display: 1, space: 1)
        let liveFail = Window(id: 99, pid: 2, app: "Term", title: "shell", frame: Frame(x: 500, y: 0, w: 500, h: 500), display: 1, space: 1)
        let yabai = FakeYabai(displays: [display], spaces: [Space(id: 1, index: 1, label: "code", display: 1)], windows: [live, liveFail])
        yabai.failFloatForWindowIds = [99]

        let restorer = SnapshotRestorer(yabai: yabai, launcher: FakeLauncher(), waiter: ImmediateWaiter())
        let snapshot = makeSnapshot([
            savedWindow(app: "Code", title: "proj", floating: true, x: 0, w: 500),
            savedWindow(app: "Term", title: "shell", floating: true, x: 500, w: 500)
        ])

        let report = try restorer.restore(snapshot)
        XCTAssertEqual(report.moved.count, 1)
        XCTAssertEqual(report.failures.count, 1)
    }

    func testPositionsOnlySkipsDisplayAndSpaceMoves() throws {
        let live = Window(id: 42, pid: 1, app: "Code", title: "proj", frame: Frame(x: 0, y: 0, w: 500, h: 500), display: 1, space: 1, isFloating: true)
        let yabai = FakeYabai(displays: [display], spaces: [Space(id: 1, index: 1, label: "code", display: 1)], windows: [live])
        let restorer = SnapshotRestorer(yabai: yabai, launcher: FakeLauncher(), waiter: ImmediateWaiter())
        let snapshot = makeSnapshot([savedWindow(app: "Code", title: "proj", floating: true, x: 0, w: 500)])

        let report = try restorer.restore(snapshot, positionsOnly: true)

        let hasDisplay = yabai.controls.contains { if case .display = $0 { return true }; return false }
        let hasSpace = yabai.controls.contains { if case .space = $0 { return true }; return false }
        let hasMove = yabai.controls.contains { if case .move = $0 { return true }; return false }
        XCTAssertFalse(hasDisplay, "positions-only must not move across displays")
        XCTAssertFalse(hasSpace, "positions-only must not move across spaces")
        XCTAssertTrue(hasMove, "positions-only still restores geometry")
        XCTAssertEqual(report.positionsOnly.count, 1)
        XCTAssertEqual(report.moved.count, 1)
        XCTAssertTrue(report.failures.isEmpty)
    }

    func testAutoFallbackDegradesWhenDisplaySpaceMoveFails() throws {
        // The Display move (attempted first) throws — e.g. no separate Spaces or
        // scripting addition. The window must degrade to positions-only, not
        // fail, and still get its geometry.
        let live = Window(id: 42, pid: 1, app: "Code", title: "proj", frame: Frame(x: 0, y: 0, w: 500, h: 500), display: 1, space: 1, isFloating: true)
        let yabai = FakeYabai(displays: [display], spaces: [Space(id: 1, index: 1, label: "code", display: 1)], windows: [live])
        yabai.failMoveForWindowIds = [42]   // toDisplay (and toSpace) throw
        let restorer = SnapshotRestorer(yabai: yabai, launcher: FakeLauncher(), waiter: ImmediateWaiter())
        let snapshot = makeSnapshot([savedWindow(app: "Code", title: "proj", floating: true, x: 0, w: 500)])

        let report = try restorer.restore(snapshot)   // default mode (auto-fallback)

        XCTAssertEqual(report.positionsOnly.count, 1, "move failure should degrade, not fail")
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertTrue(yabai.controls.contains { if case .move = $0 { return true }; return false })
    }

    func testPositionsOnlyResolvesGeometryAgainstCurrentDisplay() throws {
        // Window is LIVE on display 2, but the snapshot targets display 1. In
        // positions-only, geometry must be resolved against display 2 (where the
        // window actually is), not the planned display 1.
        let d1 = Display(id: 1, uuid: "D1", index: 1, frame: Frame(x: 0, y: 0, w: 1000, h: 1000), spaces: [1])
        let d2 = Display(id: 2, uuid: "D2", index: 2, frame: Frame(x: 1000, y: 0, w: 2000, h: 1000), spaces: [2])
        let live = Window(id: 7, pid: 1, app: "Code", title: "proj", frame: Frame(x: 1000, y: 0, w: 500, h: 500), display: 2, space: 2, isFloating: true)
        let yabai = FakeYabai(displays: [d1, d2], spaces: [], windows: [live])
        let restorer = SnapshotRestorer(yabai: yabai, launcher: FakeLauncher(), waiter: ImmediateWaiter())

        // Saved on display 1 with relativeFrame left-half (0,0,0.5,0.5).
        let savedFrame = Frame(x: 0, y: 0, w: 500, h: 500)
        let saved = WindowSnapshot(app: "Code", title: "proj", role: "AXWindow", pid: 1, space: 1, display: 1,
                                   frame: savedFrame,
                                   relativeFrame: RelativeFrame.within(d1.frame, window: savedFrame),
                                   flags: WindowFlags(floating: true, sticky: false, minimized: false, fullscreen: false))
        let snapshot = Snapshot(name: "t", capturedAt: Date(),
                                displayProfile: DisplayProfile(fingerprint: "x", displays: [d1]),
                                spaces: [], windows: [saved])

        _ = try restorer.restore(snapshot, positionsOnly: true)

        // relative (0,0,0.5,0.5) on display 2 (x:1000,w:2000) → x=1000, w=1000.
        let move = yabai.controls.compactMap { c -> (Double, Double)? in
            if case let .move(_, x, y) = c { return (x, y) }; return nil
        }.first
        XCTAssertEqual(move?.0, 1000, "geometry resolved against current display 2, not target display 1")
    }

    func testFocusedWindowIsRefocusedLast() throws {
        let a = Window(id: 1, pid: 1, app: "Code", title: "a", frame: Frame(x: 0, y: 0, w: 500, h: 500), display: 1, space: 1)
        let b = Window(id: 2, pid: 2, app: "Term", title: "b", frame: Frame(x: 500, y: 0, w: 500, h: 500), display: 1, space: 1)
        let yabai = FakeYabai(displays: [display], spaces: [], windows: [a, b])
        let restorer = SnapshotRestorer(yabai: yabai, launcher: FakeLauncher(), waiter: ImmediateWaiter())

        var focusedSaved = savedWindow(app: "Term", title: "b", floating: false, x: 500, w: 500)
        focusedSaved.focused = true
        let snapshot = makeSnapshot([
            savedWindow(app: "Code", title: "a", floating: false, x: 0, w: 500),
            focusedSaved
        ])

        _ = try restorer.restore(snapshot)
        // The last control call must be a focus on Term (window id 2).
        XCTAssertEqual(yabai.controls.last, .focus(id: 2))
    }

    func testCapturerRecordsFocusedWindow() throws {
        let focused = Window(id: 5, pid: 1, app: "Code", title: "x", frame: Frame(x: 0, y: 0, w: 500, h: 500), display: 1, space: 1, hasFocus: true)
        let other = Window(id: 6, pid: 2, app: "Term", title: "y", frame: Frame(x: 0, y: 0, w: 500, h: 500), display: 1, space: 1, hasFocus: false)
        let yabai = FakeYabai(displays: [display], spaces: [], windows: [focused, other])
        let snapshot = try SnapshotCapturer(yabai: yabai).capture(name: "f", at: Date())
        XCTAssertEqual(snapshot.windows.first(where: { $0.app == "Code" })?.focused, true)
        XCTAssertEqual(snapshot.windows.first(where: { $0.app == "Term" })?.focused, false)
    }

    func testMinimizedAndFullscreenFlagsAreRestored() throws {
        let minWin = Window(id: 1, pid: 1, app: "Code", title: "m", frame: Frame(x: 0, y: 0, w: 500, h: 500), display: 1, space: 1)
        let fsWin = Window(id: 2, pid: 2, app: "Term", title: "f", frame: Frame(x: 500, y: 0, w: 500, h: 500), display: 1, space: 1)
        let yabai = FakeYabai(displays: [display], spaces: [], windows: [minWin, fsWin])
        let restorer = SnapshotRestorer(yabai: yabai, launcher: FakeLauncher(), waiter: ImmediateWaiter())

        var minimized = savedWindow(app: "Code", title: "m", floating: false, x: 0, w: 500)
        minimized.flags.minimized = true
        var full = savedWindow(app: "Term", title: "f", floating: true, x: 500, w: 500)
        full.flags.fullscreen = true
        let snapshot = makeSnapshot([minimized, full])

        _ = try restorer.restore(snapshot)

        XCTAssertTrue(yabai.controls.contains(.minimize(id: 1, on: true)))
        XCTAssertTrue(yabai.controls.contains(.fullscreen(id: 2, on: true)))
        // A fullscreen window must NOT get move/resize even though it's floating.
        XCTAssertFalse(yabai.controls.contains { if case .move(let id, _, _) = $0 { return id == 2 }; return false })
    }

    func testBlockingStatesAreClearedBeforeMoving() throws {
        // A window that is live-minimized/fullscreen must be un-blocked before
        // yabai is asked to move it, otherwise the move fails (codex review).
        let live = Window(id: 1, pid: 1, app: "Code", title: "m", frame: Frame(x: 0, y: 0, w: 500, h: 500), display: 1, space: 1, isMinimized: true, isNativeFullscreen: true)
        let yabai = FakeYabai(displays: [display], spaces: [], windows: [live])
        let restorer = SnapshotRestorer(yabai: yabai, launcher: FakeLauncher(), waiter: ImmediateWaiter())
        let snapshot = makeSnapshot([savedWindow(app: "Code", title: "m", floating: false, x: 0, w: 500)])

        _ = try restorer.restore(snapshot)

        let firstMove = yabai.controls.firstIndex { if case .display = $0 { return true }; return false }
        let clearMin = yabai.controls.firstIndex(of: .minimize(id: 1, on: false))
        let clearFs = yabai.controls.firstIndex(of: .fullscreen(id: 1, on: false))
        XCTAssertNotNil(firstMove)
        XCTAssertNotNil(clearMin)
        XCTAssertNotNil(clearFs)
        XCTAssertLessThan(clearMin!, firstMove!, "minimize must be cleared before moving")
        XCTAssertLessThan(clearFs!, firstMove!, "fullscreen must be cleared before moving")
    }

    func testFloatingWindowGetsMoveAndResize() throws {
        let live = Window(id: 42, pid: 1, app: "Code", title: "proj", frame: Frame(x: 0, y: 0, w: 500, h: 500), display: 1, space: 1, isFloating: true)
        let yabai = FakeYabai(displays: [display], spaces: [], windows: [live])
        let restorer = SnapshotRestorer(yabai: yabai, launcher: FakeLauncher(), waiter: ImmediateWaiter())
        let snapshot = makeSnapshot([savedWindow(app: "Code", title: "proj", floating: true, x: 0, w: 500)])

        _ = try restorer.restore(snapshot)
        let didMove = yabai.controls.contains { if case .move = $0 { return true }; return false }
        let didResize = yabai.controls.contains { if case .resize = $0 { return true }; return false }
        XCTAssertTrue(didMove)
        XCTAssertTrue(didResize)
    }

    func testUnifiedDiscoveryVisitsDesktopsAndRestoresFocus() throws {
        let spaces = [
            Space(id: 1, index: 1, label: "code", display: 1, hasFocus: true),
            Space(id: 2, index: 2, label: "web", display: 1)
        ]
        let live = Window(id: 42, pid: 1, app: "Code", title: "proj",
                          frame: Frame(x: 0, y: 0, w: 500, h: 500), display: 1, space: 1)
        let yabai = FakeYabai(displays: [display], spaces: spaces, windows: [live])
        let discovery = YabaiVirtualDesktopWindowDiscovery(yabai: yabai, waiter: ImmediateWaiter())

        XCTAssertEqual(try discovery.discover().map(\.id), [42])
        let focusedSpaces = yabai.controls.compactMap { control -> Int? in
            if case let .focusSpace(index) = control { return index }
            return nil
        }
        XCTAssertEqual(focusedSpaces, [1, 2, 1])
    }

    func testUnifiedSnapshotUsesDesktopDiscovery() throws {
        final class Discovery: VirtualDesktopWindowDiscovering, @unchecked Sendable {
            var called = false
            let windows: [Window]
            init(_ windows: [Window]) { self.windows = windows }
            func discover() throws -> [Window] { called = true; return windows }
        }
        let live = Window(id: 42, pid: 1, app: "Code", title: "proj",
                          frame: Frame(x: 0, y: 0, w: 500, h: 500), display: 1, space: 1)
        let yabai = FakeYabai(displays: [display], spaces: [Space(id: 1, index: 1, label: "code", display: 1)], windows: [])
        let discovery = Discovery([live])
        let restorer = SnapshotRestorer(yabai: yabai, launcher: FakeLauncher(), waiter: ImmediateWaiter(), desktopWindowDiscovery: discovery)
        var snapshot = makeSnapshot([savedWindow(app: "Code", title: "proj", floating: false, x: 0, w: 500)])
        snapshot.spaceMode = .unifiedDesktop

        let report = try restorer.restore(snapshot)
        XCTAssertTrue(discovery.called)
        XCTAssertEqual(report.moved.count, 1)
    }
}
