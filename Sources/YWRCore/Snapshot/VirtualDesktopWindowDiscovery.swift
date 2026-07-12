import Foundation

public protocol VirtualDesktopWindowDiscovering: Sendable {
    func discover() throws -> [Window]
}

public struct YabaiVirtualDesktopWindowDiscovery: VirtualDesktopWindowDiscovering {
    private let yabai: YabaiQuerying & YabaiControlling
    private let waiter: Waiter
    private let activationWaitSeconds: Double

    public init(
        yabai: YabaiQuerying & YabaiControlling,
        waiter: Waiter = RealWaiter(),
        activationWaitSeconds: Double = 0.3
    ) {
        self.yabai = yabai
        self.waiter = waiter
        self.activationWaitSeconds = activationWaitSeconds
    }

    public func discover() throws -> [Window] {
        let spaces = try yabai.querySpaces()
            .filter { !$0.isNativeFullscreen }
            .sorted { $0.index < $1.index }
        let originalSpace = spaces.first(where: { $0.hasFocus })?.index
        guard !spaces.isEmpty else { return try yabai.queryWindows() }
        defer {
            if let originalSpace { try? yabai.focusSpace(index: originalSpace) }
        }

        var windowsByID: [Int: Window] = [:]
        for space in spaces {
            try yabai.focusSpace(index: space.index)
            waiter.wait(seconds: activationWaitSeconds)
            for window in try yabai.queryWindows() { windowsByID[window.id] = window }
        }
        return Array(windowsByID.values)
    }
}
