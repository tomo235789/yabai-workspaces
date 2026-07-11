import XCTest
@testable import YWRCore

final class SpaceProvisionerTests: XCTestCase {
    private func saved(_ index: Int, _ label: String, display: Int = 1) -> SpaceSnapshot {
        SpaceSnapshot(index: index, label: label, display: display)
    }
    private func current(_ index: Int, _ label: String, display: Int = 1) -> Space {
        Space(id: index, index: index, label: label, display: display)
    }

    func testRequestsMissingLabeledSpace() {
        let reqs = SpaceProvisioner().requests(
            savedSpaces: [saved(1, "code"), saved(2, "web")],
            currentSpaces: [current(1, "code")],
            displayMap: [1: 2]
        )
        XCTAssertEqual(reqs, [SpaceProvisionRequest(displayIndex: 2, label: "web")])
    }

    func testIgnoresEmptyLabelsAndExisting() {
        let reqs = SpaceProvisioner().requests(
            savedSpaces: [saved(1, ""), saved(2, "code")],
            currentSpaces: [current(1, "code")],
            displayMap: [:]
        )
        XCTAssertTrue(reqs.isEmpty)
    }

    func testDeduplicatesLabelsAndFallsBackToSavedDisplay() {
        let reqs = SpaceProvisioner().requests(
            savedSpaces: [saved(1, "dup", display: 3), saved(2, "dup", display: 3)],
            currentSpaces: [],
            displayMap: [:]  // no mapping → fall back to saved display index
        )
        XCTAssertEqual(reqs, [SpaceProvisionRequest(displayIndex: 3, label: "dup")])
    }
}

final class SpaceRestoreTests: XCTestCase {
    private let display = Display(id: 1, uuid: "D1", index: 1, frame: Frame(x: 0, y: 0, w: 1000, h: 1000), spaces: [1])

    func testCreateSpacesProvisionsMissingLabeledSpace() throws {
        // Saved has a "web" space that the current config lacks.
        let snapshot = Snapshot(
            name: "t", capturedAt: Date(),
            displayProfile: DisplayProfile(fingerprint: "1000x1000", displays: [display]),
            spaces: [SpaceSnapshot(index: 1, label: "code", display: 1),
                     SpaceSnapshot(index: 2, label: "web", display: 1)],
            windows: []
        )
        let yabai = FakeYabai(displays: [display],
                              spaces: [Space(id: 1, index: 1, label: "code", display: 1)],
                              windows: [])
        let restorer = SnapshotRestorer(yabai: yabai, launcher: FakeLauncher(), waiter: ImmediateWaiter())

        _ = try restorer.restore(snapshot, createSpaces: true)

        let created = yabai.controls.contains { if case .createSpace(let d) = $0 { return d == 1 }; return false }
        let labeled = yabai.controls.contains { if case .label(_, let l) = $0 { return l == "web" }; return false }
        XCTAssertTrue(created, "expected a space to be created on display 1")
        XCTAssertTrue(labeled, "expected the new space to be labeled 'web'")
    }

    func testProvisioningFailureDoesNotAbortRestore() throws {
        // createSpace fails, but the window still gets moved (best-effort provisioning).
        let win = Window(id: 1, pid: 1, app: "Code", title: "x", frame: Frame(x: 0, y: 0, w: 500, h: 500), display: 1, space: 1)
        let snapshot = Snapshot(
            name: "t", capturedAt: Date(),
            displayProfile: DisplayProfile(fingerprint: "1000x1000", displays: [display]),
            spaces: [SpaceSnapshot(index: 2, label: "web", display: 1)],
            windows: [WindowSnapshot(app: "Code", title: "x", role: "AXWindow", pid: 1, space: 1, display: 1,
                                     frame: Frame(x: 0, y: 0, w: 500, h: 500),
                                     relativeFrame: RelativeFrame(x: 0, y: 0, w: 0.5, h: 0.5),
                                     flags: WindowFlags(floating: false, sticky: false, minimized: false, fullscreen: false))]
        )
        let yabai = FakeYabai(displays: [display], spaces: [], windows: [win])
        yabai.failCreateSpaceForDisplays = [1]
        let restorer = SnapshotRestorer(yabai: yabai, launcher: FakeLauncher(), waiter: ImmediateWaiter())

        let report = try restorer.restore(snapshot, createSpaces: true)  // must not throw
        XCTAssertEqual(report.moved.count, 1)
    }

    func testProvisionRequestsIsPureAndDoesNotMutate() throws {
        let snapshot = Snapshot(
            name: "t", capturedAt: Date(),
            displayProfile: DisplayProfile(fingerprint: "1000x1000", displays: [display]),
            spaces: [SpaceSnapshot(index: 2, label: "web", display: 1)],
            windows: []
        )
        let yabai = FakeYabai(displays: [display], spaces: [], windows: [])
        let restorer = SnapshotRestorer(yabai: yabai, launcher: FakeLauncher(), waiter: ImmediateWaiter())
        let reqs = try restorer.provisionRequests(for: snapshot)
        XCTAssertEqual(reqs.map(\.label), ["web"])
        XCTAssertTrue(yabai.controls.isEmpty, "dry provisioning must not mutate")
    }
}

final class SignalInstallerTests: XCTestCase {
    func testInstallAddsThreeSignalsWithCorrectArgs() throws {
        let runner = FakeCommandRunner { _, _ in CommandResult(exitCode: 0, stdout: "", stderr: "") }
        let installer = SignalInstaller(runner: runner, ywrInvocation: "/usr/local/bin/ywr restore --auto")
        try installer.install()

        let adds = runner.calls.filter { $0.arguments.contains("--add") }
        XCTAssertEqual(adds.count, 3)
        let events = adds.compactMap { $0.arguments.first { $0.hasPrefix("event=") } }
        XCTAssertEqual(Set(events), ["event=display_added", "event=display_removed", "event=display_moved"])
        XCTAssertTrue(adds.allSatisfy { $0.arguments.contains("action=/usr/local/bin/ywr restore --auto") })
    }

    func testInstallThrowsOnFailure() {
        let runner = FakeCommandRunner { _, _ in CommandResult(exitCode: 1, stdout: "", stderr: "boom") }
        let installer = SignalInstaller(runner: runner, ywrInvocation: "ywr restore --auto")
        XCTAssertThrowsError(try installer.install())
    }

    func testUninstallReturnsFailuresWithoutThrowing() {
        let runner = FakeCommandRunner { _, _ in CommandResult(exitCode: 1, stdout: "", stderr: "not found") }
        let installer = SignalInstaller(runner: runner, ywrInvocation: "ywr restore --auto")
        let errors = installer.uninstall()  // must not throw
        XCTAssertEqual(errors.count, 3)
        let removes = runner.calls.filter { $0.arguments.contains("--remove") }
        XCTAssertEqual(removes.count, 3)
    }

    func testInstallRollsBackOnMidwayFailure() {
        var addCount = 0
        let runner = FakeCommandRunner { _, args in
            if args.contains("--add") {
                addCount += 1
                return CommandResult(exitCode: addCount == 2 ? 1 : 0, stdout: "", stderr: addCount == 2 ? "boom" : "")
            }
            return CommandResult(exitCode: 0, stdout: "", stderr: "")
        }
        let installer = SignalInstaller(runner: runner, ywrInvocation: "ywr restore --auto")
        XCTAssertThrowsError(try installer.install())
        // The first (successful) signal must be rolled back after the 2nd fails.
        let removes = runner.calls.filter { $0.arguments.contains("--remove") }
        XCTAssertEqual(removes.count, 1)
        XCTAssertTrue(removes.first!.arguments.contains("ywr_display_added"))
    }

    func testInstalledLabels() {
        let installer = SignalInstaller(runner: FakeCommandRunner(), ywrInvocation: "ywr restore --auto")
        XCTAssertEqual(installer.installedLabels(), ["ywr_display_added", "ywr_display_removed", "ywr_display_moved"])
    }
}
