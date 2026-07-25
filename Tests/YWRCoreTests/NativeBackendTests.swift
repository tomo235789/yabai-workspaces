import XCTest
@testable import YWRCore

private final class FakeEnumerator: NativeWindowEnumerating, @unchecked Sendable {
    let windows: [Window]
    init(_ windows: [Window]) {
        self.windows = windows
    }

    func enumerate() -> [Window] {
        windows
    }
}

private final class FakeController: NativeWindowControlling, @unchecked Sendable {
    struct Call: Equatable { let pid: Int; let windowID: UInt32; let frame: Frame }
    private(set) var calls: [Call] = []
    private(set) var raises: [(pid: Int, windowID: UInt32)] = []
    var failForPids: Set<Int> = []
    struct Boom: Error {}
    func setFrame(pid: Int, windowID: UInt32, to frame: Frame) throws {
        if failForPids.contains(pid) {
            throw Boom()
        }
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
            liveWindow(1, app: "Code", title: "proj", pid: 100, x: 10, w: 300),
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
            liveWindow(1, app: "Code", title: "proj", pid: 100, x: 10, w: 300),
        ])).capture(name: "n", at: Date())
        // (snap has the saved frame x=10 w=300)

        let report = restorer.restore(snap)
        XCTAssertEqual(report.positionsOnly.count, 1)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(controller.calls.count, 1)
        XCTAssertEqual(controller.calls[0].pid, 555) // uses the LIVE pid
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
            liveWindow(30, app: "C", title: "3", pid: 503),
        ]
        let controller = FakeController()
        let restorer = NativeRestorer(enumerator: FakeEnumerator(live), controller: controller)
        let saved: [WindowSnapshot] = [10, 20, 30].map { id in
            WindowSnapshot(app: String(UnicodeScalar(64 + id / 10)!), title: String(id / 10),
                           role: "AXWindow", pid: id, space: 0, display: 0, // saved pids differ from live
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
                           flags: WindowFlags(floating: true, sticky: false, minimized: false, fullscreen: false)),
        ]
        let snap = Snapshot(name: "n", capturedAt: Date(),
                            displayProfile: DisplayProfile(fingerprint: "native", displays: []),
                            spaces: [], windows: saved)

        let report = restorer.restore(snap)
        XCTAssertEqual(report.failures.count, 2) // Code setFrame throws → failed; Safari → unmatched
        XCTAssertEqual(report.failed.count, 1) // Code matched but setFrame threw
        XCTAssertEqual(report.unmatched.count, 1) // Safari not running
        XCTAssertNotNil(report.firstFailureReason)
        XCTAssertTrue(report.moved.isEmpty)
    }

    // MARK: - Walking (multi-desktop) restore

    /// Simulates desktops: a window can only be moved while ITS Space is active,
    /// and switching clamps at the ends (macOS doesn't wrap). Also serves as the
    /// switcher + active-Space identifier. Space id = index + 1 so every desktop
    /// (even "empty" ones) is uniquely identified.
    private final class FakeSpaces: SpaceSwitching, ActiveSpaceIdentifying, NativeWindowControlling, @unchecked Sendable {
        let count: Int
        let pidSpace: [Int: Int] // live pid -> desktop it lives on
        var current: Int
        private(set) var movedPids: [Int] = []
        private(set) var raisedPids: [Int] = []
        struct Boom: Error {}

        init(count: Int, pidSpace: [Int: Int], start: Int = 0) {
            self.count = count
            self.pidSpace = pidSpace
            current = start
        }

        /// macOS clamps at the ends (no wrap): a switch past the edge is a no-op.
        func switchToNextSpace() {
            current = min(current + 1, count - 1)
        }

        func switchToPreviousSpace() {
            current = max(current - 1, 0)
        }

        func currentSpaceID() -> UInt64 {
            UInt64(current + 1)
        } // unique per desktop
        func setFrame(pid: Int, windowID _: UInt32, to _: Frame) throws {
            guard pidSpace[pid] == current else { throw Boom() } // movable only on its active desktop
            movedPids.append(pid)
        }

        func raise(pid: Int, windowID _: UInt32) throws {
            raisedPids.append(pid)
        }
    }

    private func walkingSnapshot(_ live: [Window]) -> Snapshot {
        NativeCapturer(enumerator: FakeEnumerator(live)).capture(name: "n", at: Date())
    }

    func testWalkingRestorePlacesWindowsAcrossDesktopsAndReturnsHome() {
        // Two desktops: Code (pid 1) on desktop 0, Safari (pid 2) on desktop 1.
        let live = [liveWindow(1, app: "Code", title: "a", pid: 1),
                    liveWindow(2, app: "Safari", title: "b", pid: 2)]
        let spaces = FakeSpaces(count: 2, pidSpace: [1: 0, 2: 1], start: 0)
        let restorer = WalkingNativeRestorer(
            enumerator: FakeEnumerator(live), controller: spaces,
            switcher: spaces, probe: spaces, waitForSwitch: {}, maxSpaces: 16
        )

        let report = restorer.restore(walkingSnapshot(live))

        XCTAssertEqual(report.moved.count, 2) // both placed, on their own desktops
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(Set(spaces.movedPids), [1, 2])
        XCTAssertEqual(spaces.current, 0) // returned to the starting desktop
    }

    func testWalkingRestoreFromMiddleDesktopCoversBothDirections() {
        // Three desktops, STARTING ON THE MIDDLE one. Code (pid 1) lives on the
        // leftmost desktop (0) — only reachable by walking left first — and Notes
        // (pid 3) on the rightmost (2). A right-only walk would miss Code.
        let live = [liveWindow(1, app: "Code", title: "a", pid: 1),
                    liveWindow(3, app: "Notes", title: "c", pid: 3)]
        let spaces = FakeSpaces(count: 3, pidSpace: [1: 0, 3: 2], start: 1)
        let restorer = WalkingNativeRestorer(
            enumerator: FakeEnumerator(live), controller: spaces,
            switcher: spaces, probe: spaces, waitForSwitch: {}, maxSpaces: 16
        )

        let report = restorer.restore(walkingSnapshot(live))

        XCTAssertEqual(report.moved.count, 2) // both placed despite the left-edge one
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(spaces.current, 1) // returned to the middle (home)
    }

    func testWalkingRestoreCoversEmptyAdjacentDesktops() {
        // Desktop 1 (middle) is EMPTY; the target lives on desktop 2. On-screen
        // window sets can't tell an empty desktop from another, but the Space id
        // can, so the walk must not stop early at the empty one.
        let live = [liveWindow(1, app: "Code", title: "a", pid: 1)]
        let spaces = FakeSpaces(count: 3, pidSpace: [1: 2], start: 0)
        let restorer = WalkingNativeRestorer(
            enumerator: FakeEnumerator(live), controller: spaces,
            switcher: spaces, probe: spaces, waitForSwitch: {}, maxSpaces: 16
        )

        let report = restorer.restore(walkingSnapshot(live))

        XCTAssertEqual(report.moved.count, 1) // reached desktop 2 past the empty one
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(spaces.current, 0) // returned home
    }

    func testWalkingRestorePlacesOnLastDesktopWhenCapReached() {
        // maxSpaces == 1 allows exactly one switch (desktops 0→1). The window is
        // on desktop 1 (the last reachable one); it must still be placed, not
        // dropped because the cap was hit.
        let live = [liveWindow(1, app: "Code", title: "a", pid: 1)]
        let spaces = FakeSpaces(count: 2, pidSpace: [1: 1], start: 0)
        let restorer = WalkingNativeRestorer(
            enumerator: FakeEnumerator(live), controller: spaces,
            switcher: spaces, probe: spaces, waitForSwitch: {}, maxSpaces: 1
        )

        let report = restorer.restore(walkingSnapshot(live))

        XCTAssertEqual(report.moved.count, 1) // placed on the last reached desktop
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(spaces.current, 0) // returned home
    }

    func testWalkingRestoreDoesNotRaiseAWindowOnAnotherDesktop() {
        // Frontmost saved window (index 0, pid 1) lives on desktop 1; home is 0.
        // Raising it would yank macOS to desktop 1, so it must NOT be raised.
        let live = [liveWindow(1, app: "Code", title: "a", pid: 1),
                    liveWindow(2, app: "Safari", title: "b", pid: 2)]
        let spaces = FakeSpaces(count: 2, pidSpace: [1: 1, 2: 0], start: 0)
        let restorer = WalkingNativeRestorer(
            enumerator: FakeEnumerator(live), controller: spaces,
            switcher: spaces, probe: spaces, waitForSwitch: {}, maxSpaces: 16
        )

        _ = restorer.restore(walkingSnapshot(live))

        XCTAssertEqual(spaces.current, 0) // stayed home
        XCTAssertEqual(spaces.raisedPids, [2]) // raised the home window, not the pid-1 one
    }

    func testWalkingRestoreWithNoMatchesDoesNotFlipDesktops() {
        // Saved app isn't running → nothing to place. The walk must not switch
        // desktops at all (no pointless screen flipping).
        let live = [liveWindow(1, app: "Code", title: "a", pid: 1)] // live
        let saved = [liveWindow(2, app: "Safari", title: "b", pid: 2)] // saved (absent app)
        let spaces = FakeSpaces(count: 3, pidSpace: [:], start: 1)
        let restorer = WalkingNativeRestorer(
            enumerator: FakeEnumerator(live), controller: spaces,
            switcher: spaces, probe: spaces, waitForSwitch: {}, maxSpaces: 16
        )

        let report = restorer.restore(walkingSnapshot(saved))

        XCTAssertEqual(report.unmatched.count, 1)
        XCTAssertEqual(report.moved.count, 0)
        XCTAssertEqual(spaces.current, 1) // never left the starting desktop
    }

    func testWalkingRestoreReportsUnreachableWindow() {
        // The Notes window's pid maps to no desktop, so it can never be placed.
        let live = [liveWindow(1, app: "Code", title: "a", pid: 1),
                    liveWindow(9, app: "Notes", title: "z", pid: 9)]
        let spaces = FakeSpaces(count: 3, pidSpace: [1: 0], start: 0)
        let restorer = WalkingNativeRestorer(
            enumerator: FakeEnumerator(live), controller: spaces,
            switcher: spaces, probe: spaces, waitForSwitch: {}, maxSpaces: 16
        )

        let report = restorer.restore(walkingSnapshot(live))

        XCTAssertEqual(report.moved.count, 1) // Code placed
        XCTAssertEqual(report.failed.count, 1) // Notes never reachable
        XCTAssertEqual(spaces.current, 0) // ends where it started
    }
}
