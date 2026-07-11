import XCTest
@testable import YWRCore

final class AutoSelectorTests: XCTestCase {
    private func display(uuid: String, w: Double, h: Double, index: Int = 1) -> Display {
        Display(id: index, uuid: uuid, index: index, frame: Frame(x: 0, y: 0, w: w, h: h), spaces: [1])
    }

    private func snapshot(name: String, displays: [Display]) -> Snapshot {
        Snapshot(name: name, capturedAt: Date(),
                 displayProfile: DisplayProfile(fingerprint: name, displays: displays),
                 spaces: [], windows: [])
    }

    func testEmptyReturnsNone() {
        let selector = AutoSelector()
        if case .none = selector.select(from: [], currentDisplays: [display(uuid: "A", w: 1000, h: 1000)]) {
            // ok
        } else {
            XCTFail("expected .none")
        }
    }

    func testConfidentWhenOneClearMatch() {
        let selector = AutoSelector()
        let home = snapshot(name: "home", displays: [display(uuid: "HOME", w: 1728, h: 1117)])
        let office = snapshot(name: "office", displays: [display(uuid: "OFFICE", w: 3840, h: 2160)])
        let current = [display(uuid: "HOME", w: 1728, h: 1117)]

        if case let .confident(scored) = selector.select(from: [home, office], currentDisplays: current) {
            XCTAssertEqual(scored.snapshot.name, "home")
        } else {
            XCTFail("expected .confident(home)")
        }
    }

    func testAmbiguousWhenNoMatchReachesThreshold() {
        let selector = AutoSelector()
        // Neither saved profile matches the current display well.
        let a = snapshot(name: "a", displays: [display(uuid: "X", w: 800, h: 600)])
        let current = [display(uuid: "Y", w: 5120, h: 2880)]
        if case .ambiguous = selector.select(from: [a], currentDisplays: current) {
            // ok — surfaced for the user to choose
        } else {
            XCTFail("expected .ambiguous")
        }
    }

    func testAmbiguousWhenTwoEquallyGoodMatches() {
        let selector = AutoSelector()
        // Two snapshots with the identical display → identical scores → ambiguous.
        let shared = display(uuid: "SAME", w: 1728, h: 1117)
        let a = snapshot(name: "a", displays: [shared])
        let b = snapshot(name: "b", displays: [shared])
        let current = [shared]
        if case let .ambiguous(candidates) = selector.select(from: [a, b], currentDisplays: current) {
            XCTAssertEqual(candidates.count, 2)
        } else {
            XCTFail("expected .ambiguous with 2 candidates")
        }
    }
}
