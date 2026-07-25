import XCTest
@testable import YWRMenuUI

/// Recording/controllable actions for driving the view model in tests.
private final class FakeActions: WorkspaceActions, @unchecked Sendable {
    var names: [String]
    var restoreResult: String
    var saveShouldThrow: Bool
    private(set) var savedNames: [String] = []

    init(names: [String] = [], restoreResult: String = "done", saveShouldThrow: Bool = false) {
        self.names = names
        self.restoreResult = restoreResult
        self.saveShouldThrow = saveShouldThrow
    }

    struct SaveError: Error {}
    private(set) var restoredNames: [String] = []

    func snapshotNames() async -> [String] { names }
    func save(name: String) async throws {
        if saveShouldThrow { throw SaveError() }
        savedNames.append(name)
        names.append(name)
    }
    func restore(name: String) async throws -> String {
        restoredNames.append(name)
        return "Restored '\(name)'"
    }
    func restoreAuto() async throws -> String { restoreResult }
}

@MainActor
final class MenuViewModelTests: XCTestCase {
    func testRefreshLoadsSnapshotNames() async {
        let model = MenuViewModel(actions: FakeActions(names: ["home", "office"]))
        await model.refresh()
        XCTAssertEqual(model.snapshots, ["home", "office"])
    }

    func testSaveTrimsNameUpdatesStatusAndRefreshes() async {
        let actions = FakeActions()
        let model = MenuViewModel(actions: actions, newName: "  home  ")
        await model.save()
        XCTAssertEqual(actions.savedNames, ["home"])          // trimmed
        XCTAssertEqual(model.status, "Saved 'home'")
        XCTAssertEqual(model.newName, "")                     // cleared
        XCTAssertEqual(model.snapshots, ["home"])             // refreshed
        XCTAssertFalse(model.isBusy)                          // reset after work
    }

    func testSaveWithEmptyNamePrompts() async {
        let actions = FakeActions()
        let model = MenuViewModel(actions: actions, newName: "   ")
        await model.save()
        XCTAssertEqual(model.status, "Enter a name")
        XCTAssertTrue(actions.savedNames.isEmpty)
    }

    func testSaveFailureShowsError() async {
        let model = MenuViewModel(actions: FakeActions(saveShouldThrow: true), newName: "home")
        await model.save()
        XCTAssertTrue(model.status.hasPrefix("Save failed:"))
    }

    func testRestoreByNameCallsActionAndSetsStatus() async {
        let actions = FakeActions(names: ["home", "office"])
        let model = MenuViewModel(actions: actions)
        await model.restore(name: "office")
        XCTAssertEqual(actions.restoredNames, ["office"])
        XCTAssertEqual(model.status, "Restored 'office'")
        XCTAssertFalse(model.isBusy)
    }

    func testRestoreAutoSetsStatus() async {
        let model = MenuViewModel(actions: FakeActions(restoreResult: "Restored 'home': 3 moved, 0 failed"))
        await model.restoreAuto()
        XCTAssertEqual(model.status, "Restored 'home': 3 moved, 0 failed")
        XCTAssertFalse(model.isBusy)
    }

    func testReentrantSaveIsIgnoredWhileBusy() async {
        // Seeding isBusy via a first in-flight call is awkward to force
        // deterministically; instead verify the guard: a model marked busy
        // (by starting a slow action) rejects a second call. We approximate by
        // checking that calling save twice concurrently only saves once.
        let actions = SlowActions()
        let model = MenuViewModel(actions: actions, newName: "home")
        async let a: Void = model.save()
        async let b: Void = model.save()
        _ = await (a, b)
        XCTAssertEqual(actions.saveCount, 1, "re-entrant save must be ignored while busy")
    }
}

/// Actions whose save suspends, so two overlapping saves exercise the busy guard.
private final class SlowActions: WorkspaceActions, @unchecked Sendable {
    private(set) var saveCount = 0
    func snapshotNames() async -> [String] { [] }
    func save(name: String) async throws {
        saveCount += 1
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    func restore(name: String) async throws -> String { "" }
    func restoreAuto() async throws -> String { "" }
}
