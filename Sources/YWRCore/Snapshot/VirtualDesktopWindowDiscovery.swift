import Foundation

public protocol VirtualDesktopWindowDiscovering: Sendable {
    func discover() throws -> [Window]
}

public enum VirtualDesktopDiscoveryError: Error, CustomStringConvertible {
    case allQueriesFailed

    public var description: String {
        "virtual-desktop discovery could not query any Space's windows"
    }
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

    /// Implemented via ollama qwen3-coder-next, reviewed and integrated.
    /// Visits every Space (including native-fullscreen ones, so their windows are
    /// observed) and is best-effort per Space so one un-focusable Space doesn't
    /// abort discovery. Seeds with the currently-visible windows first.
    public func discover() throws -> [Window] {
        let allSpaces = try yabai.querySpaces()
        let originalSpace = allSpaces.first(where: { $0.hasFocus })?.index
        let sortedSpaces = allSpaces.sorted(by: { $0.index < $1.index })

        if sortedSpaces.isEmpty {
            return try yabai.queryWindows()
        }

        var windowsByID: [Int: Window] = [:]
        var anyQuerySucceeded = false

        // Seed with currently visible windows (best-effort).
        if let seeded = try? yabai.queryWindows() {
            anyQuerySucceeded = true
            for window in seeded {
                windowsByID[window.id] = window
            }
        }

        defer {
            if let originalSpace {
                try? yabai.focusSpace(index: originalSpace)
            }
        }

        for space in sortedSpaces {
            do {
                try yabai.focusSpace(index: space.index)
                waiter.wait(seconds: activationWaitSeconds)
                let windowsInSpace = try yabai.queryWindows()
                anyQuerySucceeded = true
                for window in windowsInSpace {
                    windowsByID[window.id] = window
                }
            } catch {
                continue
            }
        }

        // If NOT ONE query succeeded, report failure so the restorer's fallback
        // runs instead of planning against an empty (falsely "successful") set.
        guard anyQuerySucceeded else {
            throw VirtualDesktopDiscoveryError.allQueriesFailed
        }
        return Array(windowsByID.values)
    }
}
