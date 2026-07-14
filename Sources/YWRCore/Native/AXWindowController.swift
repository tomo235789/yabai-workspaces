import Foundation
import ApplicationServices

// Implemented via ollama qwen3-coder-next, reviewed and integrated with fixes:
//   - removed a duplicate `Frame` definition (it lives in the models),
//   - removed `CFRelease` (Swift manages CoreFoundation lifetimes via ARC).
//
// ROADMAP / PoC: move/resize a window via the Accessibility API, independent of
// yabai. Needs Accessibility permission and a GUI session, so it's verified on
// device. Matching is by owner pid + window title (CGWindowID isn't exposed by
// the public AX API); a title collision falls back to the first window.
public enum AXWindowError: Error, CustomStringConvertible {
    case appHasNoWindows(pid: Int)
    case windowNotFound(pid: Int, title: String)
    case setFailed(String)

    public var description: String {
        switch self {
        case .appHasNoWindows(let pid):
            return "application with PID \(pid) has no accessible windows"
        case .windowNotFound(let pid, let title):
            return "window titled '\(title)' not found in application PID \(pid)"
        case .setFailed(let detail):
            return "failed to set window attribute: \(detail)"
        }
    }
}

public protocol NativeWindowControlling: Sendable {
    func setFrame(pid: Int, matchTitle: String, to frame: Frame) throws
}

public struct AXWindowController: NativeWindowControlling {
    public init() {}

    public func setFrame(pid: Int, matchTitle: String, to frame: Frame) throws {
        let app = AXUIElementCreateApplication(pid_t(pid))

        guard let windows = copyWindows(app), !windows.isEmpty else {
            throw AXWindowError.appHasNoWindows(pid: pid)
        }

        let targetWindow: AXUIElement
        if matchTitle.isEmpty {
            targetWindow = windows[0]
        } else if let match = windows.first(where: { copyStringAttribute($0, kAXTitleAttribute) == matchTitle }) {
            targetWindow = match
        } else {
            throw AXWindowError.windowNotFound(pid: pid, title: matchTitle)
        }

        var point = CGPoint(x: frame.x, y: frame.y)
        guard let positionValue = AXValueCreate(.cgPoint, &point) else {
            throw AXWindowError.setFailed("position (AXValueCreate failed)")
        }
        if AXUIElementSetAttributeValue(targetWindow, kAXPositionAttribute as CFString, positionValue) != .success {
            throw AXWindowError.setFailed("position")
        }

        var size = CGSize(width: frame.w, height: frame.h)
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw AXWindowError.setFailed("size (AXValueCreate failed)")
        }
        if AXUIElementSetAttributeValue(targetWindow, kAXSizeAttribute as CFString, sizeValue) != .success {
            throw AXWindowError.setFailed("size")
        }
    }

    private func copyStringAttribute(_ element: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func copyWindows(_ app: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }
}
