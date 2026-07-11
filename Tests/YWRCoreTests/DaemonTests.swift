import XCTest
@testable import YWRCore

final class DaemonTests: XCTestCase {
    private func display(uuid: String, w: Double, h: Double) -> Display {
        Display(id: 1, uuid: uuid, index: 1, frame: Frame(x: 0, y: 0, w: w, h: h), spaces: [1])
    }

    private func snapshot(name: String, displays: [Display]) -> Snapshot {
        Snapshot(name: name, capturedAt: Date(),
                 displayProfile: DisplayProfile(fingerprint: name, displays: displays),
                 spaces: [], windows: [])
    }

    // MARK: - DisplayMonitor

    func testMonitorReportsOnlyOnChange() {
        // A, A, B, B, C  → changes at A, B, C (3 reports over 5 polls)
        let watcher = FakeDisplayWatcher(sequence: ["A", "A", "B", "B", "C"])
        let handler = RecordingHandler()
        let monitor = DisplayMonitor(watcher: watcher, handler: handler, waiter: ImmediateWaiter())

        monitor.poll(iterations: 5, startingFingerprint: nil)

        XCTAssertEqual(handler.changes.map(\.to), ["A", "B", "C"])
        XCTAssertEqual(handler.changes.first?.from, nil)
    }

    func testMonitorDoesNotReportWhenStartingFingerprintMatches() {
        let watcher = FakeDisplayWatcher(sequence: ["A", "A"])
        let handler = RecordingHandler()
        let monitor = DisplayMonitor(watcher: watcher, handler: handler, waiter: ImmediateWaiter())

        monitor.poll(iterations: 2, startingFingerprint: "A")
        XCTAssertTrue(handler.changes.isEmpty)
    }

    func testMonitorSurvivesTransientPollErrors() {
        // Call 1 throws; the loop must keep going and still report B afterwards.
        let watcher = FakeDisplayWatcher(sequence: ["A", "A", "B"], throwOnCalls: [1])
        let handler = RecordingHandler()
        let logger = CapturingLogger()
        let monitor = DisplayMonitor(watcher: watcher, handler: handler, waiter: ImmediateWaiter(), logger: logger)

        monitor.poll(iterations: 3, startingFingerprint: nil)

        XCTAssertEqual(handler.changes.map(\.to), ["A", "B"])
        XCTAssertTrue(logger.lines.contains { $0.contains("Poll failed") })
    }

    // MARK: - AutoRestoreHandler

    func testHandlerRestoresConfidentMatch() {
        let d = display(uuid: "HOME", w: 1728, h: 1117)
        let yabai = FakeYabai(displays: [d])
        let store = FakeSnapshotStore(snapshots: [snapshot(name: "home", displays: [d])])
        let logger = CapturingLogger()

        var restored: [String] = []
        let handler = AutoRestoreHandler(
            yabai: yabai, store: store,
            restore: { snap in restored.append(snap.name); return RestoreReport() },
            logger: logger
        )

        handler.handleChange(from: nil, to: "1728x1117")
        XCTAssertEqual(restored, ["home"])
        XCTAssertTrue(logger.lines.contains { $0.contains("Auto-restoring 'home'") })
    }

    func testHandlerSkipsWhenNoSnapshots() {
        let d = display(uuid: "X", w: 800, h: 600)
        let yabai = FakeYabai(displays: [d])
        let store = FakeSnapshotStore(snapshots: [])
        let logger = CapturingLogger()

        var restoreCalls = 0
        let handler = AutoRestoreHandler(
            yabai: yabai, store: store,
            restore: { _ in restoreCalls += 1; return RestoreReport() },
            logger: logger
        )

        handler.handleChange(from: "old", to: "new")
        XCTAssertEqual(restoreCalls, 0)
        XCTAssertTrue(logger.lines.contains { $0.contains("No snapshots to restore") })
    }
}
