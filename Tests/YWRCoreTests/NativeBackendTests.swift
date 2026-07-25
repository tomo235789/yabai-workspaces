import XCTest
@testable import YWRCore

private final class FakeEnumerator: NativeWindowEnumerating, @unchecked Sendable {
    let windows: [Window]
    init(_ windows: [Window]) { self.windows = windows }
    func enumerate() -> [Window] { windows }
}

private final class FakeController: NativeWindowControlling, @unchecked Sendable {
    struct Call: Equatable { let pid: Int; let windowID: UInt32; let frame: Frame }
    private(set) var calls: [Call] = []
    private(set) var raises: [(pid: Int, windowID: UInt32)] = []
    var failForPids: Set<Int> = []
    struct Boom: Error {}
    func setFrame(pid: Int, windowID: UInt32, to frame: Frame) throws {
        if failForPids.contains(pid) { throw Boom() }
        calls.append(Call(pid: pid, windowID: windowID, frame: frame))
    }
    func raise(pid: Int, windowID: UInt32) throws {
        raises.append((pid: pid, windowID: windowID))
    }
}

private func liveWindow(_ id: Int, app: String, title: String, pid: Int, x: Double = 0, w: Double = 100) -> Window {
    Window(id: id, pid: pid, app: app, title: title, frame: Frame(x: x, y: 0, w: w, h: 100), display: 0, space: 0)
}

final class NativeBackendTests: XCTestCase {
    func testCaptureBuildsPositionsOnlySnapshot() {
        let cap = NativeCapturer(enumerator: FakeEnumerator([
            liveWindow(1, app: "Code", title: "proj", pid: 100, x: 10, w: 300)
        ]))
        let snap = cap.capture(name: "n", at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(snap.displayProfile.fingerprint, "native")
        XCTAssertEqual(snap.windows.count, 1)
        XCTAssertEqual(snap.windows[0].app, "Code")
        XCTAssertEqual(snap.windows[0].frame, Frame(x: 10, y: 0, w: 300, h: 100))
        XCTAssertEqual(snap.windows[0].display, 0)
        XCTAssertTrue(snap.windows[0].flags.floating)
    }

    func testRestoreSetsFramesForMatchedWindows() {
        // Live windows have new pids/positions; restore should move them back.
        let live = [liveWindow(1, app: "Code", title: "proj", pid: 555, x: 999, w: 50)]
        let controller = FakeController()
        let restorer = NativeRestorer(enumerator: FakeEnumerator(live), controller: controller)

        var snap = NativeCapturer(enumerator: FakeEnumerator([
            liveWindow(1, app: "Code", title: "proj", pid: 100, x: 10, w: 300)
        ])).capture(name: "n", at: Date())
        // (snap has the saved frame x=10 w=300)

        let report = restorer.restore(snap)
        XCTAssertEqual(report.positionsOnly.count, 1)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(controller.calls.count, 1)
        XCTAssertEqual(controller.calls[0].pid, 555)          // uses the LIVE pid
        XCTAssertEqual(controller.calls[0].frame, Frame(x: 10, y: 0, w: 300, h: 100))
        _ = snap
    }

    func testRestoreRaisesOnlyThePreviouslyFrontmostWindowUsingLivePID() {
        // Saved order is front-to-back [10, 20, 30]; only the frontmost (10)
        // should be raised. Live windows use DISTINCT pids from the saved ones,
        // so this also verifies raise targets the LIVE window (not a stale pid).
        let live = [
            liveWindow(10, app: "A", title: "1", pid: 501),
            liveWindow(20, app: "B", title: "2", pid: 502),
            liveWindow(30, app: "C", title: "3", pid: 503)
        ]
        let controller = FakeController()
        let restorer = NativeRestorer(enumerator: FakeEnumerator(live), controller: controller)
        let saved: [WindowSnapshot] = [10, 20, 30].map { id in
            WindowSnapshot(app: String(UnicodeScalar(64 + id / 10)!), title: String(id / 10),
                           role: "AXWindow", pid: id, space: 0, display: 0,       // saved pids differ from live
                           frame: Frame(x: 0, y: 0, w: 100, h: 100),
                           relativeFrame: RelativeFrame(x: 0, y: 0, w: 0, h: 0),
                           flags: WindowFlags(floating: true, sticky: false, minimized: false, fullscreen: false))
        }
        let snap = Snapshot(name: "n", capturedAt: Date(),
                            displayProfile: DisplayProfile(fingerprint: "native", displays: []),
                            spaces: [], windows: saved)

        _ = restorer.restore(snap)
        XCTAssertEqual(controller.raises.count, 1)
        XCTAssertEqual(controller.raises.first?.windowID, 10)
        XCTAssertEqual(controller.raises.first?.pid, 501, "raise must use the LIVE window's pid")
    }

    func testRestoreReportsUnmatchedAndFailures() {
        let live = [liveWindow(1, app: "Code", title: "proj", pid: 555)]
        let controller = FakeController()
        controller.failForPids = [555]
        let restorer = NativeRestorer(enumerator: FakeEnumerator(live), controller: controller)

        let saved = [
            WindowSnapshot(app: "Code", title: "proj", role: "AXWindow", pid: 1, space: 0, display: 0,
                           frame: Frame(x: 0, y: 0, w: 100, h: 100), relativeFrame: RelativeFrame(x: 0, y: 0, w: 0, h: 0),
                           flags: WindowFlags(floating: true, sticky: false, minimized: false, fullscreen: false)),
            WindowSnapshot(app: "Safari", title: "docs", role: "AXWindow", pid: 2, space: 0, display: 0,
                           frame: Frame(x: 0, y: 0, w: 100, h: 100), relativeFrame: RelativeFrame(x: 0, y: 0, w: 0, h: 0),
                           flags: WindowFlags(floating: true, sticky: false, minimized: false, fullscreen: false))
        ]
        let snap = Snapshot(name: "n", capturedAt: Date(),
                            displayProfile: DisplayProfile(fingerprint: "native", displays: []),
                            spaces: [], windows: saved)

        let report = restorer.restore(snap)
        XCTAssertEqual(report.failures.count, 2)  // Code setFrame throws → failed; Safari → unmatched
        XCTAssertEqual(report.failed.count, 1)    // Code matched but setFrame threw
        XCTAssertEqual(report.unmatched.count, 1) // Safari not running
        XCTAssertNotNil(report.firstFailureReason)
        XCTAssertTrue(report.moved.isEmpty)
    }
}
