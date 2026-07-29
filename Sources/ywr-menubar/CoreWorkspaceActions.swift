import Foundation
import YWRCore
import YWRMenuUI

/// Concrete `WorkspaceActions` backed by YWRCore — the composition root for the
/// menu-bar app. Implemented as an `actor` so its blocking work (yabai
/// subprocess calls, waiting for launched apps) runs off the main actor and the
/// menu-bar UI stays responsive. The UI depends only on the `WorkspaceActions`
/// abstraction (Dependency Inversion).
actor CoreWorkspaceActions: WorkspaceActions {
    private let store: FileSnapshotStore
    private let capturer: SnapshotCapturer
    private let restorer: SnapshotRestorer
    private let availability: YabaiAvailability
    private let nativeCapturer: NativeCapturer
    private let nativeRestorer: NativeRestorer
    private let nativeWalker: WalkingNativeRestorer
    private let logger: any EventLogging

    init(logger: any EventLogging = ConsoleLogger()) {
        let runner = ProcessCommandRunner()
        let paths = Paths()
        let client = YabaiClient(runner: runner)
        store = FileSnapshotStore(paths: paths)
        capturer = SnapshotCapturer(yabai: client, spaceModeDetector: MacOSSpaceModeDetector(runner: runner))
        restorer = SnapshotRestorer(yabai: client, launcher: AppLauncher(runner: runner))
        availability = YabaiAvailability(runner: runner)
        let nativeEnumerator = CGWindowEnumerator()
        let nativeController = AXWindowController()
        nativeCapturer = NativeCapturer(enumerator: nativeEnumerator)
        nativeRestorer = NativeRestorer(enumerator: nativeEnumerator, controller: nativeController)
        nativeWalker = WalkingNativeRestorer(enumerator: nativeEnumerator, controller: nativeController)
        self.logger = logger
    }

    /// Optional external theme file: `~/.config/yabai-workspaces/theme.json`.
    /// `nonisolated` so the SwiftUI App can resolve it synchronously at launch.
    nonisolated static func themeConfigURL() -> URL? {
        let url = Paths().root.appendingPathComponent("theme.json")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func snapshotNames() async -> [String] {
        do {
            return try store.list().map(\.name)
        } catch {
            logger.log("Failed to list snapshots: \(error)")
            return []
        }
    }

    func save(name: String) async throws {
        // Fall back to the yabai-independent backend when yabai isn't running,
        // mirroring the CLI so the menu-bar app works in yabai-less setups too.
        let snapshot: Snapshot = if availability.isAvailable() {
            try capturer.capture(name: name, at: Date())
        } else {
            nativeCapturer.capture(name: name, at: Date())
        }
        try store.save(snapshot)
    }

    func restore(name: String) async throws -> String {
        let snapshot = try store.load(name: name)
        // A native snapshot must be restored by the native backend even if yabai
        // is now available — the yabai planner can't handle its zeroed geometry.
        let isNative = snapshot.displayProfile.fingerprint == NativeCapturer.nativeFingerprint
        if availability.isAvailable(), !isNative {
            let report = try restorer.restore(snapshot)
            let po = report.positionsOnly.count
            let poNote = po > 0 ? " (\(po) positions-only)" : ""
            return "Restored '\(name)': \(report.moved.count) moved, \(report.failures.count) failed\(poNote)"
        } else {
            let report = nativeRestorer.restore(snapshot)
            return nativeStatus(name: name, report: report)
        }
    }

    /// Restore across every desktop by walking Spaces. Always uses the native
    /// walker (the whole point is repositioning windows on other desktops, which
    /// only the native/AX path does). The screen will flip through each desktop.
    func restoreAcrossDesktops(name: String) async throws -> String {
        let snapshot = try store.load(name: name)
        let report = nativeWalker.restore(snapshot)
        return nativeStatus(name: name, report: report)
    }

    /// Human-readable native-restore result. Always reports the real counts and
    /// the first failure reason; adds an Accessibility-permission hint ONLY when
    /// the failures look like an authorization problem (AX couldn't read any of
    /// an app's windows) — not for unrelated failures like a window that closed.
    private nonisolated func nativeStatus(name: String, report: RestoreReport) -> String {
        let moved = report.moved.count
        let failed = report.failed.count
        let unmatched = report.unmatched.count
        var parts = ["\(moved) repositioned"]
        if failed > 0 {
            parts.append("\(failed) failed")
        }
        if unmatched > 0 {
            parts.append("\(unmatched) not running")
        }
        var msg = "Restored '\(name)' (native): " + parts.joined(separator: ", ")
        if moved == 0, failed > 0 {
            if let reason = report.firstFailureReason, Self.looksLikeMissingAccessibility(reason) {
                msg += ". Grant Accessibility permission to 'yabai workspaces' in System Settings."
            } else if let reason = report.firstFailureReason {
                msg += " (\(reason))"
            }
        }
        return msg
    }

    /// AX reports "no accessible windows" when it can't read an app's window
    /// list at all — the classic symptom of a missing/stale Accessibility grant.
    private nonisolated static func looksLikeMissingAccessibility(_ reason: String) -> Bool {
        reason.contains("no accessible windows")
    }

    func delete(name: String) async throws {
        try store.delete(name: name)
    }
}
