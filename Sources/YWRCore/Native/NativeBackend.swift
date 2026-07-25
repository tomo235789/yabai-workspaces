import Foundation
import CoreGraphics

// Implemented via ollama qwen3-coder-next, reviewed and integrated.
//
// The yabai-independent backend: capture/restore window GEOMETRY only, using
// CGWindowList enumeration + AXUIElement move/resize. Works in configurations
// where yabai can't run ("Displays have separate Spaces" off). It is inherently
// positions-only — the public macOS APIs can't assign windows to Spaces/Displays.

public struct NativeCapturer {
    private let enumerator: NativeWindowEnumerating

    public init(enumerator: NativeWindowEnumerating) {
        self.enumerator = enumerator
    }

    public func capture(name: String, at date: Date) -> Snapshot {
        let windows = enumerator.enumerate()
        let mappedWindows = windows.map { window in
            WindowSnapshot(
                app: window.app,
                title: window.title,
                role: "AXWindow",
                pid: window.pid,
                space: 0,
                display: 0,
                frame: window.frame,
                relativeFrame: RelativeFrame(x: 0, y: 0, w: 0, h: 0),
                flags: WindowFlags(floating: true, sticky: false, minimized: false, fullscreen: false)
            )
        }

        return Snapshot(
            version: Snapshot.currentVersion,
            name: name,
            capturedAt: date,
            displayProfile: DisplayProfile(fingerprint: "native", displays: []),
            spaces: [],
            windows: mappedWindows
        )
    }
}

public struct NativeRestorer {
    private let enumerator: NativeWindowEnumerating
    private let controller: NativeWindowControlling
    private let matcher: WindowMatching

    public init(enumerator: NativeWindowEnumerating, controller: NativeWindowControlling, matcher: WindowMatching = WindowMatcher()) {
        self.enumerator = enumerator
        self.controller = controller
        self.matcher = matcher
    }

    public func restore(_ snapshot: Snapshot) -> RestoreReport {
        var available = enumerator.enumerate()
        var outcomes: [RestoreOutcome] = []

        for saved in snapshot.windows {
            let label = "\(saved.app) — \(saved.title.isEmpty ? "(untitled)" : saved.title)"

            if let match = matcher.bestMatch(for: saved, among: available) {
                available.removeAll { $0.id == match.id }
                do {
                    try controller.setFrame(pid: match.pid, windowID: CGWindowID(match.id), to: saved.frame)
                    outcomes.append(RestoreOutcome(label: label, status: .movedPositionsOnly))
                } catch {
                    outcomes.append(RestoreOutcome(label: label, status: .failed(reason: "\(error)")))
                }
            } else {
                outcomes.append(RestoreOutcome(label: label, status: .unmatched))
            }
        }

        return RestoreReport(outcomes: outcomes)
    }
}
