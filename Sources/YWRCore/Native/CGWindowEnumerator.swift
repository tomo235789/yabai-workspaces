import Foundation
import CoreGraphics

// Implemented via ollama qwen3-coder-next, reviewed and integrated.
//
// ROADMAP / PoC: yabai-independent, on-screen window enumeration via
// CoreGraphics. Returns [Window] with display/space unknown (0) — the native
// backend targets positions-only restore that works even when yabai can't run
// (e.g. "Displays have separate Spaces" off). Titles require screen-recording
// permission; geometry does not. Verified on device.
public protocol NativeWindowEnumerating: Sendable {
    func enumerate() -> [Window]
}

public struct CGWindowEnumerator: NativeWindowEnumerating {
    public init() {}

    public func enumerate() -> [Window] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) else {
            return []
        }
        guard let infoArray = windowList as? [[String: Any]] else {
            return []
        }
        return NativeWindowMapper.windows(from: infoArray)
    }
}
