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
    func setFloating(_ id: Int, _ floating: Bool) throws {
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
