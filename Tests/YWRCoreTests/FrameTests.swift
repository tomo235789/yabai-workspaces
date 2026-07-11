import XCTest
@testable import YWRCore

final class FrameTests: XCTestCase {
    func testRelativeFrameRoundTripsOnSameDisplay() {
        let display = Frame(x: 0, y: 0, w: 1000, h: 800)
        let window = Frame(x: 100, y: 80, w: 500, h: 400)

        let relative = RelativeFrame.within(display, window: window)
        XCTAssertEqual(relative.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(relative.y, 0.1, accuracy: 0.0001)
        XCTAssertEqual(relative.w, 0.5, accuracy: 0.0001)
        XCTAssertEqual(relative.h, 0.5, accuracy: 0.0001)

        XCTAssertEqual(relative.resolved(on: display), window)
    }

    func testRelativeFrameScalesToDifferentDisplay() {
        let saved = Frame(x: 0, y: 0, w: 1000, h: 1000)
        let window = Frame(x: 500, y: 0, w: 500, h: 1000) // right half
        let relative = RelativeFrame.within(saved, window: window)

        let current = Frame(x: 2000, y: 100, w: 3840, h: 2160)
        let resolved = relative.resolved(on: current)
        XCTAssertEqual(resolved.x, 2000 + 1920, accuracy: 0.001)
        XCTAssertEqual(resolved.w, 1920, accuracy: 0.001)
        XCTAssertEqual(resolved.h, 2160, accuracy: 0.001)
    }

    func testHandlesZeroSizedDisplayWithoutNaN() {
        let display = Frame(x: 0, y: 0, w: 0, h: 0)
        let window = Frame(x: 0, y: 0, w: 100, h: 100)
        let relative = RelativeFrame.within(display, window: window)
        XCTAssertFalse(relative.w.isNaN)
        XCTAssertFalse(relative.h.isNaN)
    }
}
