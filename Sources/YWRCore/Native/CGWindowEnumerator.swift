import AppKit
import CoreGraphics
import Foundation

/// ROADMAP / PoC: yabai-independent, on-screen window enumeration via
/// CoreGraphics. Returns [Window] with display/space unknown (0) — the native
/// backend targets positions-only restore that works even when yabai can't run
/// (e.g. "Displays have separate Spaces" off). Window titles require Screen
/// Recording permission; geometry does not. Verified on device.
public protocol NativeWindowEnumerating: Sendable {
    func enumerate() -> [Window]
}

public struct CGWindowEnumerator: NativeWindowEnumerating {
    public init() {}

    public func enumerate() -> [Window] {
        // Deliberately NOT .optionOnScreenOnly: that would omit windows on other
        // Spaces (and minimized ones), silently producing an incomplete capture.
        guard let windowList = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) else {
            return []
        }
        guard let infoArray = windowList as? [[String: Any]] else {
            return []
        }
        // Keep only windows owned by regular GUI apps — this drops the large
        // amount of noise from system/helper/agent processes (Window Server,
        // *ViewService, Open and Save Panel Service, Spotlight, loginwindow, …).
        return NativeWindowMapper.windows(from: infoArray, regularAppPIDs: regularAppPIDs())
    }

    private func regularAppPIDs() -> Set<Int> {
        Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .map { Int($0.processIdentifier) }
        )
    }
}
