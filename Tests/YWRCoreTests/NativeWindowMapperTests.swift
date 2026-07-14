import XCTest
@testable import YWRCore

final class NativeWindowMapperTests: XCTestCase {
    private func entry(id: Any, pid: Any = 100, owner: Any = "Code", title: String? = "proj",
                       layer: Any = 0, x: Any = 10, y: Any = 20, w: Any = 300, h: Any = 400) -> [String: Any] {
        var d: [String: Any] = [
            "kCGWindowNumber": id,
            "kCGWindowOwnerPID": pid,
            "kCGWindowOwnerName": owner,
            "kCGWindowLayer": layer,
            "kCGWindowBounds": ["X": x, "Y": y, "Width": w, "Height": h]
        ]
        if let title { d["kCGWindowName"] = title }
        return d
    }

    func testMapsBasicWindow() {
        let w = NativeWindowMapper.windows(from: [entry(id: 42)])
        XCTAssertEqual(w.count, 1)
        XCTAssertEqual(w[0].id, 42)
        XCTAssertEqual(w[0].pid, 100)
        XCTAssertEqual(w[0].app, "Code")
        XCTAssertEqual(w[0].title, "proj")
        XCTAssertEqual(w[0].frame, Frame(x: 10, y: 20, w: 300, h: 400))
        XCTAssertTrue(w[0].isFloating)
    }

    func testCoercesNSNumberAndDouble() {
        let e = entry(id: NSNumber(value: 7), pid: NSNumber(value: 9),
                      x: 1.5, y: NSNumber(value: 2.0), w: 100.0, h: NSNumber(value: 50))
        let w = NativeWindowMapper.windows(from: [e])
        XCTAssertEqual(w.count, 1)
        XCTAssertEqual(w[0].id, 7)
        XCTAssertEqual(w[0].frame, Frame(x: 1.5, y: 2, w: 100, h: 50))
    }

    func testSkipsNonZeroLayer() {
        XCTAssertTrue(NativeWindowMapper.windows(from: [entry(id: 1, layer: 25)]).isEmpty)
    }

    func testSkipsZeroSizeAndEmptyOwner() {
        XCTAssertTrue(NativeWindowMapper.windows(from: [entry(id: 1, w: 0)]).isEmpty)
        XCTAssertTrue(NativeWindowMapper.windows(from: [entry(id: 1, h: -5)]).isEmpty)
        XCTAssertTrue(NativeWindowMapper.windows(from: [entry(id: 1, owner: "")]).isEmpty)
    }

    func testMissingTitleBecomesEmpty() {
        let w = NativeWindowMapper.windows(from: [entry(id: 1, title: nil)])
        XCTAssertEqual(w.count, 1)
        XCTAssertEqual(w[0].title, "")
    }

    func testPreservesOrderAndFiltersMix() {
        let list = [entry(id: 1), entry(id: 2, layer: 3), entry(id: 3)]
        XCTAssertEqual(NativeWindowMapper.windows(from: list).map(\.id), [1, 3])
    }
}
