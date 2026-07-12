import Foundation
import YWRCore

/// Scriptable CommandRunner: maps a matched argument prefix to a canned result.
final class FakeCommandRunner: CommandRunner, @unchecked Sendable {
    struct Call: Equatable { let executable: String; let arguments: [String] }
    private(set) var calls: [Call] = []
    var handler: (String, [String]) -> CommandResult

    init(handler: @escaping (String, [String]) -> CommandResult = { _, _ in
        CommandResult(exitCode: 0, stdout: "", stderr: "")
    }) {
        self.handler = handler
    }

    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        calls.append(Call(executable: executable, arguments: arguments))
        return handler(executable, arguments)
    }
}

/// In-memory yabai that returns fixed state and records control calls.
final class FakeYabai: YabaiQuerying, YabaiControlling, @unchecked Sendable {
    var displays: [Display]
    var spaces: [Space]
    var windows: [Window]

    enum Control: Equatable {
        case space(id: Int, index: Int)
        case display(id: Int, index: Int)
        case float(id: Int, on: Bool)
        case move(id: Int, x: Double, y: Double)
        case resize(id: Int, w: Double, h: Double)
        case focus(id: Int)
        case label(index: Int, label: String)
        case createSpace(display: Int)
        case minimize(id: Int, on: Bool)
        case fullscreen(id: Int, on: Bool)
    }
    private(set) var controls: [Control] = []
    var failMoveForWindowIds: Set<Int> = []

    init(displays: [Display] = [], spaces: [Space] = [], windows: [Window] = []) {
        self.displays = displays
        self.spaces = spaces
        self.windows = windows
    }

    func queryDisplays() throws -> [Display] { displays }
    func querySpaces() throws -> [Space] { spaces }
    func queryWindows() throws -> [Window] { windows }

    struct BoomError: Error {}

    func moveWindow(_ id: Int, toSpace spaceIndex: Int) throws {
        if failMoveForWindowIds.contains(id) { throw BoomError() }
        controls.append(.space(id: id, index: spaceIndex))
    }
    func moveWindow(_ id: Int, toDisplay displayIndex: Int) throws {
        if failMoveForWindowIds.contains(id) { throw BoomError() }
        controls.append(.display(id: id, index: displayIndex))
    }
    var failFloatForWindowIds: Set<Int> = []
    func setFloating(_ id: Int, _ floating: Bool) throws {
        if failFloatForWindowIds.contains(id) { throw BoomError() }
        controls.append(.float(id: id, on: floating))
    }
    func moveWindow(_ id: Int, toX x: Double, y: Double) throws {
        controls.append(.move(id: id, x: x, y: y))
    }
    func resizeWindow(_ id: Int, toW w: Double, h: Double) throws {
        controls.append(.resize(id: id, w: w, h: h))
    }
    func focusWindow(_ id: Int) throws { controls.append(.focus(id: id)) }
    func labelSpace(index: Int, label: String) throws { controls.append(.label(index: index, label: label)) }
    var failCreateSpaceForDisplays: Set<Int> = []
    private var nextSpaceIndex = 100
    func createSpace(onDisplay displayIndex: Int) throws {
        if failCreateSpaceForDisplays.contains(displayIndex) { throw BoomError() }
        controls.append(.createSpace(display: displayIndex))
        // Mimic yabai: a new unlabeled space appears on that display.
        spaces.append(Space(id: nextSpaceIndex, index: nextSpaceIndex, label: "", display: displayIndex))
        nextSpaceIndex += 1
    }
    func setMinimized(_ id: Int, _ minimized: Bool) throws { controls.append(.minimize(id: id, on: minimized)) }
    func setFullscreen(_ id: Int, _ fullscreen: Bool) throws { controls.append(.fullscreen(id: id, on: fullscreen)) }
}

/// AppLauncher fake: never really launches; can inject "appeared" windows.
final class FakeLauncher: AppLaunching, @unchecked Sendable {
    private(set) var launched: [String] = []
    var failFor: Set<String> = []

    struct BoomError: Error {}

    func isRunning(_ appName: String, windows: [Window]) -> Bool {
        windows.contains { $0.app == appName }
    }
    func launch(_ appName: String) throws {
        if failFor.contains(appName) { throw BoomError() }
        launched.append(appName)
    }
}

struct ImmediateWaiter: Waiter {
    func wait(seconds: Double) {}
}

/// Emits a scripted sequence of fingerprints, one per `runOnce` call. Calls
/// whose 0-based index is in `throwOnCalls` throw instead, to exercise the
/// daemon's transient-failure resilience.
final class FakeDisplayWatcher: DisplayWatching, @unchecked Sendable {
    private var sequence: [String]
    private let throwOnCalls: Set<Int>
    private(set) var callCount = 0

    struct BoomError: Error {}

    init(sequence: [String], throwOnCalls: Set<Int> = []) {
        self.sequence = sequence
        self.throwOnCalls = throwOnCalls
    }

    func runOnce(previousFingerprint: String?) throws -> String {
        let call = callCount
        callCount += 1
        if throwOnCalls.contains(call) { throw BoomError() }
        // Clamp to the last value once the script is exhausted.
        let idx = min(call, sequence.count - 1)
        return sequence[idx]
    }
}

/// Records every change the monitor reports.
final class RecordingHandler: DisplayChangeHandling, @unchecked Sendable {
    private(set) var changes: [(from: String?, to: String)] = []
    func handleChange(from oldFingerprint: String?, to newFingerprint: String) {
        changes.append((oldFingerprint, newFingerprint))
    }
}

/// Captures log lines for assertions.
final class CapturingLogger: EventLogging, @unchecked Sendable {
    private(set) var lines: [String] = []
    func log(_ message: String) { lines.append(message) }
}

/// In-memory SnapshotStore for handler tests.
final class FakeSnapshotStore: SnapshotStore, @unchecked Sendable {
    var snapshots: [Snapshot]
    init(snapshots: [Snapshot] = []) { self.snapshots = snapshots }

    func save(_ snapshot: Snapshot) throws { snapshots.append(snapshot) }
    func load(name: String) throws -> Snapshot {
        guard let s = snapshots.first(where: { $0.name == name }) else {
            throw SnapshotStoreError.notFound(name: name)
        }
        return s
    }
    func list() throws -> [SnapshotSummary] {
        snapshots.map { SnapshotSummary(name: $0.name, fingerprint: $0.displayProfile.fingerprint,
                                        capturedAt: $0.capturedAt, windowCount: $0.windows.count, spaceCount: $0.spaces.count) }
    }
    func loadAll() throws -> [Snapshot] { snapshots }
    func exists(name: String) -> Bool { snapshots.contains { $0.name == name } }
}
