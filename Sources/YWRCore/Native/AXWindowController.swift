import Foundation
import ApplicationServices

// Implemented via ollama qwen3-coder-next, reviewed and integrated with fixes:
//   - removed a duplicate `Frame` definition, renamed the frame helper to avoid
//     shadowing the `currentFrame` parameter, replaced unsafe bitcasts with
//     bridging casts, and used AXValueGetValue's Bool result correctly.
//
// ROADMAP / PoC: move/resize a window via the Accessibility API, independent of
// yabai. Matching is by owner pid + title, disambiguated by the window whose
// CURRENT geometry is closest to `currentFrame` (the CGWindowList frame of the
// matched window) — so multiple same-title / untitled windows target correctly.
// Needs Accessibility permission; verified on device.
public enum AXWindowError: Error, CustomStringConvertible {
    case appHasNoWindows(pid: Int)
    case windowNotFound(pid: Int, title: String)
    case setFailed(String)

    public var description: String {
        switch self {
        case .appHasNoWindows(let pid):
            return "application PID \(pid) has no accessible windows"
        case .windowNotFound(let pid, let title):
            return "window titled '\(title)' not found in application PID \(pid)"
        case .setFailed(let message):
            return "failed to set window frame: \(message)"
        }
    }
}

public protocol NativeWindowControlling: Sendable {
    func setFrame(pid: Int, matchTitle: String, currentFrame: Frame, to frame: Frame) throws
}

public struct AXWindowController: NativeWindowControlling {
    public init() {}

    public func setFrame(pid: Int, matchTitle: String, currentFrame: Frame, to frame: Frame) throws {
        let app = AXUIElementCreateApplication(pid_t(pid))

        guard let windows = copyWindows(app), !windows.isEmpty else {
            throw AXWindowError.appHasNoWindows(pid: pid)
        }

        let candidates: [AXUIElement]
        if matchTitle.isEmpty {
            candidates = windows
        } else {
            let titled = windows.filter { copyStringAttribute($0, kAXTitleAttribute) == matchTitle }
            guard !titled.isEmpty else {
                throw AXWindowError.windowNotFound(pid: pid, title: matchTitle)
            }
            candidates = titled
        }

        // Disambiguate by the candidate whose current geometry is closest to the
        // matched window's known frame; unreadable frames rank worst.
        var best: AXUIElement?
        var bestDistance = Double.infinity
        for window in candidates {
            guard let f = axFrame(of: window) else { continue }
            let dx = f.x - currentFrame.x, dy = f.y - currentFrame.y
            let dw = f.w - currentFrame.w, dh = f.h - currentFrame.h
            let distance = dx * dx + dy * dy + dw * dw + dh * dh
            if distance < bestDistance {
                bestDistance = distance
                best = window
            }
        }
        let window = best ?? candidates[0]

        var position = CGPoint(x: frame.x, y: frame.y)
        guard let positionValue = AXValueCreate(.cgPoint, &position) else {
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

    private func copyWindows(_ app: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }

    private func copyStringAttribute(_ element: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func axFrame(of window: AXUIElement) -> Frame? {
        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              let pos = positionValue, CFGetTypeID(pos) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(unsafeDowncast(pos, to: AXValue.self), .cgPoint, &point) else { return nil }

        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let sz = sizeValue, CFGetTypeID(sz) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(sz, to: AXValue.self), .cgSize, &size) else { return nil }

        return Frame(x: Double(point.x), y: Double(point.y), w: Double(size.width), h: Double(size.height))
    }
}
