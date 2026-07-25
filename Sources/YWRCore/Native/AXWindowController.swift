import Foundation
import ApplicationServices
import CoreGraphics
import AppKit

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
        case .appHasNoWindows(let pid):
            return "application PID \(pid) has no accessible windows"
        case .windowNotFound(let pid, let windowID):
            return "window \(windowID) not found in application PID \(pid)"
        case .setFailed(let message):
            return "failed to set window frame: \(message)"
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
        let window = try resolveWindow(pid: pid, windowID: windowID)

        var point = CGPoint(x: frame.x, y: frame.y)
        guard let positionValue = AXValueCreate(.cgPoint, &point) else {
            throw AXWindowError.setFailed("position (AXValueCreate failed)")
        }
        if AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue) != .success {
            throw AXWindowError.setFailed("position")
        }

        var size = CGSize(width: frame.w, height: frame.h)
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw AXWindowError.setFailed("size (AXValueCreate failed)")
        }
        if AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) != .success {
            throw AXWindowError.setFailed("size")
        }
    }

    public func raise(pid: Int, windowID: UInt32) throws {
        let window = try resolveWindow(pid: pid, windowID: windowID)
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        // Activating the app in back-to-front order builds up global z-order.
        NSRunningApplication(processIdentifier: pid_t(pid))?.activate()
    }

    // MARK: - Helpers

    private func resolveWindow(pid: Int, windowID: UInt32) throws -> AXUIElement {
        let app = AXUIElementCreateApplication(pid_t(pid))
        // Electron/Chromium apps only expose their AX window tree once this is set.
        _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        guard let windows = copyWindows(app), !windows.isEmpty else {
            throw AXWindowError.appHasNoWindows(pid: pid)
        }
        guard let window = windows.first(where: { cgWindowID(of: $0) == windowID }) else {
            throw AXWindowError.windowNotFound(pid: pid, windowID: windowID)
        }
        return window
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
