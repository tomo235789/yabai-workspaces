import XCTest
@testable import YWRCore

final class StoreAndCaptureTests: XCTestCase {
    private func tempPaths() -> Paths {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ywr-tests-\(UUID().uuidString)", isDirectory: true)
        return Paths(root: dir)
    }

    func testSnapshotRoundTripsThroughFileStore() throws {
        let paths = tempPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = FileSnapshotStore(paths: paths)

        let display = Display(id: 1, uuid: "D1", index: 1, frame: Frame(x: 0, y: 0, w: 1000, h: 1000), spaces: [1])
        let win = WindowSnapshot(app: "Code", title: "t", role: "AXWindow", pid: 1, space: 1, display: 1,
                                 frame: Frame(x: 0, y: 0, w: 500, h: 500),
                                 relativeFrame: RelativeFrame(x: 0, y: 0, w: 0.5, h: 0.5),
                                 flags: WindowFlags(floating: true, sticky: false, minimized: false, fullscreen: false))
        let snapshot = Snapshot(name: "home", capturedAt: Date(timeIntervalSince1970: 1_000_000),
                                displayProfile: DisplayProfile(fingerprint: "1000x1000", displays: [display]),
                                spaces: [SpaceSnapshot(index: 1, label: "code", display: 1)],
                                windows: [win])

        try store.save(snapshot)
        XCTAssertTrue(store.exists(name: "home"))
        XCTAssertEqual(try store.load(name: "home"), snapshot)

        let list = try store.list()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.windowCount, 1)
        XCTAssertEqual(list.first?.fingerprint, "1000x1000")
    }

    func testLoadingMissingSnapshotThrows() {
        let store = FileSnapshotStore(paths: tempPaths())
        XCTAssertThrowsError(try store.load(name: "nope"))
    }

    func testCapturerBuildsRelativeFramesAndFingerprint() throws {
        let display = Display(id: 1, uuid: "D1", index: 1, frame: Frame(x: 0, y: 0, w: 1000, h: 800), spaces: [1])
        let window = Window(id: 1, pid: 1, app: "Code", title: "proj",
                            frame: Frame(x: 100, y: 80, w: 500, h: 400), display: 1, space: 1, isFloating: true)
        let yabai = FakeYabai(displays: [display], spaces: [Space(id: 1, index: 1, label: "code", display: 1)], windows: [window])

        let capturer = SnapshotCapturer(yabai: yabai)
        let snapshot = try capturer.capture(name: "x", at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(snapshot.displayProfile.fingerprint, "1000x800")
        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.windows[0].relativeFrame.x, 0.1, accuracy: 0.0001)
        XCTAssertTrue(snapshot.windows[0].flags.floating)
    }
}

final class YabaiClientTests: XCTestCase {
    func testQueryDisplaysDecodesHyphenatedKeys() throws {
        let json = """
        [{"id":1,"uuid":"ABC","index":1,"frame":{"x":0.0,"y":0.0,"w":1728.0,"h":1117.0},"spaces":[1,2],"has-focus":true}]
        """
        let runner = FakeCommandRunner { _, args in
            args.contains("--displays")
                ? CommandResult(exitCode: 0, stdout: json, stderr: "")
                : CommandResult(exitCode: 1, stdout: "", stderr: "unexpected")
        }
        let client = YabaiClient(runner: runner)
        let displays = try client.queryDisplays()
        XCTAssertEqual(displays.count, 1)
        XCTAssertEqual(displays[0].uuid, "ABC")
        XCTAssertTrue(displays[0].hasFocus)
    }

    func testNonZeroExitThrows() {
        let runner = FakeCommandRunner { _, _ in
            CommandResult(exitCode: 1, stdout: "", stderr: "yabai not running")
        }
        let client = YabaiClient(runner: runner)
        XCTAssertThrowsError(try client.queryWindows())
    }
}
