import ApplicationServices
import CoreGraphics
import Foundation

// Robust native mover: targets a window by its CGWindowID (stable within a
// session) via the private `_AXUIElementGetWindow`, so it's independent of
// window titles (which need Screen Recording permission). Enables the AX tree
// for Electron/Chromium apps via AXManualAccessibility. Needs Accessibility
// permission; verified on device.

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

public enum AXWindowError: Error, CustomStringConvertible {
    case appHasNoWindows(pid: Int)
    case windowNotFound(pid: Int, windowID: UInt32)
    case setFailed(String)

    public var description: String {
        switch self {
        case let .appHasNoWindows(pid):
            "application PID \(pid) has no accessible windows"
        case let .windowNotFound(pid, windowID):
            "window \(windowID) not found in application PID \(pid)"
        case let .setFailed(message):
            "failed to set window frame: \(message)"
        }
    }
}

public protocol NativeWindowControlling: Sendable {
    func setFrame(pid: Int, windowID: UInt32, to frame: Frame) throws
    /// Brings the window to the front (within its app) and activates the app.
    /// Called back-to-front during restore to reproduce the saved stacking order.
    func raise(pid: Int, windowID: UInt32) throws
}

public struct AXWindowController: NativeWindowControlling {
    public init() {}

    public func setFrame(pid: Int, windowID: UInt32, to frame: Frame) throws {
        let (_, window) = try resolve(pid: pid, windowID: windowID)

        // Position uses global coordinates spanning all displays, so setting it
        // moves the window across monitors. But AX clamps the first setPosition
        // when the target is on another display or when the size doesn't fit yet,
        // so we set position, then size, then position AGAIN to land it exactly.
        try setPosition(window, x: frame.x, y: frame.y)
        try setSize(window, w: frame.w, h: frame.h)
        try setPosition(window, x: frame.x, y: frame.y)
    }

    private func setPosition(_ window: AXUIElement, x: Double, y: Double) throws {
        var point = CGPoint(x: x, y: y)
        guard let value = AXValueCreate(.cgPoint, &point) else {
            throw AXWindowError.setFailed("position (AXValueCreate failed)")
        }
        if AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) != .success {
            throw AXWindowError.setFailed("position")
        }
    }

    private func setSize(_ window: AXUIElement, w: Double, h: Double) throws {
        var size = CGSize(width: w, height: h)
        guard let value = AXValueCreate(.cgSize, &size) else {
            throw AXWindowError.setFailed("size (AXValueCreate failed)")
        }
        if AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) != .success {
            throw AXWindowError.setFailed("size")
        }
    }

    public func raise(pid: Int, windowID: UInt32) throws {
        let (app, window) = try resolve(pid: pid, windowID: windowID)
        // Bring to front via AX: NSRunningApplication.activate() is unreliable
        // from a non-GUI CLI process, whereas an accessibility client can set the
        // app frontmost and the window main/focused directly.
        _ = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    // MARK: - Helpers

    private func resolve(pid: Int, windowID: UInt32) throws -> (app: AXUIElement, window: AXUIElement) {
        let app = AXUIElementCreateApplication(pid_t(pid))
        // Electron/Chromium apps only expose their AX window tree once this is set.
        _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        guard let windows = copyWindows(app), !windows.isEmpty else {
            throw AXWindowError.appHasNoWindows(pid: pid)
        }
        guard let window = windows.first(where: { cgWindowID(of: $0) == windowID }) else {
            throw AXWindowError.windowNotFound(pid: pid, windowID: windowID)
        }
        return (app, window)
    }

    private func copyWindows(_ app: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }

    private func cgWindowID(of window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(window, &id) == .success else { return nil }
        return id
    }
}
