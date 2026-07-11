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
        let live = Window(id: 42, pid: 1, app: "Code", title: "proj", frame: Frame(x: 0, y: 0, w: 500, h: 500), display: 1, space: 1)
        let liveFail = Window(id: 99, pid: 2, app: "Term", title: "shell", frame: Frame(x: 500, y: 0, w: 500, h: 500), display: 1, space: 1)
        let yabai = FakeYabai(displays: [display], spaces: [Space(id: 1, index: 1, label: "code", display: 1)], windows: [live, liveFail])
        yabai.failMoveForWindowIds = [99]

        let restorer = SnapshotRestorer(yabai: yabai, launcher: FakeLauncher(), waiter: ImmediateWaiter())
        let snapshot = makeSnapshot([
            savedWindow(app: "Code", title: "proj", floating: true, x: 0, w: 500),
            savedWindow(app: "Term", title: "shell", floating: true, x: 500, w: 500)
        ])

        let report = try restorer.restore(snapshot)
        XCTAssertEqual(report.moved.count, 1)
        XCTAssertEqual(report.failures.count, 1)
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
}
