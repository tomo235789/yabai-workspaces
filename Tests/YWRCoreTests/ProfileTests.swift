import XCTest
@testable import YWRCore

final class ProfileTests: XCTestCase {
    private func tempPaths() -> Paths {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ywr-profile-tests-\(UUID().uuidString)", isDirectory: true)
        return Paths(root: dir)
    }

    func testProfileRoundTripsThroughFileStore() throws {
        let paths = tempPaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = FileProfileStore(paths: paths)

        let display = Display(id: 1, uuid: "D1", index: 1, frame: Frame(x: 0, y: 0, w: 1728, h: 1117), spaces: [1, 2])
        let captured = CapturedProfile(name: "home", capturedAt: Date(timeIntervalSince1970: 500_000),
                                       profile: DisplayProfile(fingerprint: "1728x1117", displays: [display]))
        try store.save(captured)
        XCTAssertTrue(store.exists(name: "home"))
        XCTAssertEqual(try store.load(name: "home"), captured)

        let list = try store.list()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.profile.fingerprint, "1728x1117")
    }

    func testListReturnsEmptyWhenNoDirectory() throws {
        let store = FileProfileStore(paths: tempPaths())
        XCTAssertEqual(try store.list().count, 0)
    }

    func testLoadingMissingProfileThrows() {
        let store = FileProfileStore(paths: tempPaths())
        XCTAssertThrowsError(try store.load(name: "nope"))
    }

    func testCapturerGeneratesFingerprintFromDisplays() throws {
        let d1 = Display(id: 1, uuid: "A", index: 1, frame: Frame(x: 0, y: 0, w: 1728, h: 1117), spaces: [1])
        let d2 = Display(id: 2, uuid: "B", index: 2, frame: Frame(x: 1728, y: 0, w: 3840, h: 2160), spaces: [2])
        let yabai = FakeYabai(displays: [d1, d2], spaces: [], windows: [])

        let capturer = ProfileCapturer(yabai: yabai)
        let captured = try capturer.capture(name: "dual", at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(captured.profile.displays.count, 2)
        XCTAssertEqual(captured.profile.fingerprint, "1728x1117+3840x2160")
    }
}
