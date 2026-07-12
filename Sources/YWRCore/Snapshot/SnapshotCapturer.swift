import Foundation

public protocol SnapshotCapturing: Sendable {
    func capture(name: String, at date: Date) throws -> Snapshot
}

/// Builds a `Snapshot` from live yabai state. Depends only on `YabaiQuerying`
/// (not the full client) so it can't accidentally mutate anything, and on a
/// `FingerprintGenerating` abstraction for the display id.
public struct SnapshotCapturer: SnapshotCapturing {
    private let yabai: YabaiQuerying
    private let fingerprint: FingerprintGenerating
    private let spaceModeDetector: SpaceModeDetecting

    public init(yabai: YabaiQuerying, fingerprint: FingerprintGenerating = DefaultFingerprintGenerator(), spaceModeDetector: SpaceModeDetecting = FixedSpaceModeDetector(.unknown)) {
        self.yabai = yabai
        self.fingerprint = fingerprint
        self.spaceModeDetector = spaceModeDetector
    }

    public func capture(name: String, at date: Date = Date()) throws -> Snapshot {
        let displays = try yabai.queryDisplays()
        let spaces = try yabai.querySpaces()
        let windows = try yabai.queryWindows()

        let displaysByIndex = Dictionary(uniqueKeysWithValues: displays.map { ($0.index, $0) })

        let windowSnapshots: [WindowSnapshot] = windows
            // Skip windows we can't meaningfully restore (minimized/hidden with
            // zero geometry still keep their flags, but drop windows off every
            // display). The plan targets "visible or otherwise queryable".
            .compactMap { window in
                guard let display = displaysByIndex[window.display] else { return nil }
                let relative = RelativeFrame.within(display.frame, window: window.frame)
                return WindowSnapshot(
                    app: window.app,
                    title: window.title,
                    role: window.role,
                    pid: window.pid,
                    space: window.space,
                    display: window.display,
                    frame: window.frame,
                    relativeFrame: relative,
                    flags: WindowFlags(
                        floating: window.isFloating,
                        sticky: window.isSticky,
                        minimized: window.isMinimized,
                        fullscreen: window.isNativeFullscreen
                    ),
                    focused: window.hasFocus
                )
            }

        let spaceSnapshots = spaces.map {
            SpaceSnapshot(index: $0.index, label: $0.label, display: $0.display)
        }

        return Snapshot(
            name: name,
            capturedAt: date,
            spaceMode: spaceModeDetector.detect(),
            displayProfile: DisplayProfile(
                fingerprint: fingerprint.fingerprint(for: displays),
                displays: displays
            ),
            spaces: spaceSnapshots,
            windows: windowSnapshots
        )
    }
}
