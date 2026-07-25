import Foundation

// Implemented via ollama qwen3-coder-next, reviewed and integrated.
//
// ROADMAP / PoC: a yabai-independent window backend. This pure mapper turns raw
// CGWindowList output into `[Window]` so the enumeration logic is testable
// without CoreGraphics. The actual CGWindowListCopyWindowInfo call and the
// AXUIElement move/resize live in the platform layer (need Accessibility /
// screen-recording permission and a GUI session, so they're verified on device).
public enum NativeWindowMapper {
    private static func doubleValue(from value: Any) -> Double? {
        switch value {
        case let num as NSNumber: return num.doubleValue
        case let val as Double: return val
        case let val as Int: return Double(val)
        default: return nil
        }
    }

    private static func intValue(from value: Any) -> Int? {
        switch value {
        case let num as NSNumber: return num.intValue
        case let val as Int: return val
        case let val as Double: return Int(val)
        default: return nil
        }
    }

    /// - Parameter regularAppPIDs: when non-nil, only windows owned by one of
    ///   these pids are kept (used to drop system/helper-process noise).
    public static func windows(from infoList: [[String: Any]], regularAppPIDs: Set<Int>? = nil) -> [Window] {
        var result = [Window]()

        for dict in infoList {
            guard let idRaw = dict["kCGWindowNumber"],
                  let pidRaw = dict["kCGWindowOwnerPID"],
                  let ownerNameRaw = dict["kCGWindowOwnerName"],
                  let boundsRaw = dict["kCGWindowBounds"] as? [String: Any],
                  let layerRaw = dict["kCGWindowLayer"]
            else {
                continue
            }

            guard let id = intValue(from: idRaw),
                  let pid = intValue(from: pidRaw),
                  let layer = intValue(from: layerRaw)
            else {
                continue
            }

            // Skip non-application windows (layer != 0: menu bar, dock, …).
            guard layer == 0 else { continue }

            // Keep only regular GUI apps' windows when a filter is provided.
            if let regularAppPIDs, !regularAppPIDs.contains(pid) { continue }

            guard let ownerName = ownerNameRaw as? String, !ownerName.isEmpty else {
                continue
            }

            guard let xRaw = boundsRaw["X"],
                  let yRaw = boundsRaw["Y"],
                  let widthRaw = boundsRaw["Width"],
                  let heightRaw = boundsRaw["Height"]
            else {
                continue
            }

            guard let x = doubleValue(from: xRaw),
                  let y = doubleValue(from: yRaw),
                  let width = doubleValue(from: widthRaw),
                  let height = doubleValue(from: heightRaw)
            else {
                continue
            }

            guard width > 0, height > 0 else { continue }

            let title = (dict["kCGWindowName"] as? String) ?? ""
            let frame = Frame(x: x, y: y, w: width, h: height)

            result.append(Window(
                id: id,
                pid: pid,
                app: ownerName,
                title: title,
                frame: frame,
                display: 0,
                space: 0,
                isFloating: true
            ))
        }

        return result
    }
}
