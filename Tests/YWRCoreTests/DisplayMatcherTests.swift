import XCTest
@testable import YWRCore

final class DisplayMatcherTests: XCTestCase {
    private func display(id: Int, uuid: String, index: Int, x: Double, w: Double, h: Double, spaces: [Int]) -> Display {
        Display(id: id, uuid: uuid, index: index, frame: Frame(x: x, y: 0, w: w, h: h), spaces: spaces)
    }

    func testUUIDMatchScoresAboveThreshold() {
        let matcher = DisplayMatcher()
        let saved = display(id: 1, uuid: "ABC", index: 1, x: 0, w: 1728, h: 1117, spaces: [1, 2])
        let current = display(id: 9, uuid: "ABC", index: 1, x: 0, w: 1728, h: 1117, spaces: [1, 2])
        let score = matcher.score(saved: saved, current: current, allSaved: [saved], allCurrent: [current])
        XCTAssertGreaterThanOrEqual(score, 70)
    }

    func testDifferentDisplaysScoreBelowThreshold() {
        let matcher = DisplayMatcher()
        let saved = display(id: 1, uuid: "ABC", index: 1, x: 0, w: 1728, h: 1117, spaces: [1])
        let current = display(id: 2, uuid: "ZZZ", index: 1, x: 0, w: 3840, h: 2160, spaces: [1, 2, 3, 4])
        let score = matcher.score(saved: saved, current: current, allSaved: [saved], allCurrent: [current])
        XCTAssertLessThan(score, 70)
    }

    func testMatchAssignsStrongestPairFirst() {
        let matcher = DisplayMatcher()
        let builtin = display(id: 1, uuid: "BUILTIN", index: 1, x: 0, w: 1728, h: 1117, spaces: [1])
        let ext = display(id: 2, uuid: "EXT4K", index: 2, x: 1728, w: 3840, h: 2160, spaces: [2])
        let curExt = display(id: 20, uuid: "EXT4K", index: 1, x: 0, w: 3840, h: 2160, spaces: [1])
        let curBuiltin = display(id: 10, uuid: "BUILTIN", index: 2, x: 3840, w: 1728, h: 1117, spaces: [2])

        let result = matcher.match(saved: [builtin, ext], current: [curExt, curBuiltin])
        let builtinCorr = result.first { $0.savedIndex == 0 }
        XCTAssertEqual(builtinCorr?.currentDisplayIndex, 2)
        XCTAssertTrue(builtinCorr?.isConfident ?? false)
    }
}
