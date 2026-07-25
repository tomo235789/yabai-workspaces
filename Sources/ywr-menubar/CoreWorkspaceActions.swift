import Foundation
import YWRCore
import YWRMenuUI

/// Concrete `WorkspaceActions` backed by YWRCore — the composition root for the
/// menu-bar app. Implemented as an `actor` so its blocking work (yabai
/// subprocess calls, waiting for launched apps) runs off the main actor and the
/// menu-bar UI stays responsive. The UI depends only on the `WorkspaceActions`
/// abstraction (Dependency Inversion).
actor CoreWorkspaceActions: WorkspaceActions {
    private let yabai: YabaiClient
    private let store: FileSnapshotStore
    private let capturer: SnapshotCapturer
    private let restorer: SnapshotRestorer
    private let autoSelector: AutoSelector
    private let availability: YabaiAvailability
    private let nativeCapturer: NativeCapturer
    private let nativeRestorer: NativeRestorer
    private let logger: any EventLogging

    init(logger: any EventLogging = ConsoleLogger()) {
        let runner = ProcessCommandRunner()
        let paths = Paths()
        let client = YabaiClient(runner: runner)
        self.yabai = client
        self.store = FileSnapshotStore(paths: paths)
        self.capturer = SnapshotCapturer(yabai: client, spaceModeDetector: MacOSSpaceModeDetector(runner: runner))
        self.restorer = SnapshotRestorer(yabai: client, launcher: AppLauncher(runner: runner))
        self.autoSelector = AutoSelector()
        self.availability = YabaiAvailability(runner: runner)
        let nativeEnumerator = CGWindowEnumerator()
        self.nativeCapturer = NativeCapturer(enumerator: nativeEnumerator)
        self.nativeRestorer = NativeRestorer(enumerator: nativeEnumerator, controller: AXWindowController())
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
        let snapshot: Snapshot
        if availability.isAvailable() {
            snapshot = try capturer.capture(name: name, at: Date())
        } else {
            snapshot = nativeCapturer.capture(name: name, at: Date())
        }
        try store.save(snapshot)
    }

    func restore(name: String) async throws -> String {
        let snapshot = try store.load(name: name)
        // A native snapshot must be restored by the native backend even if yabai
        // is now available — the yabai planner can't handle its zeroed geometry.
        let isNative = snapshot.displayProfile.fingerprint == NativeCapturer.nativeFingerprint
        if availability.isAvailable() && !isNative {
            let report = try restorer.restore(snapshot)
            let po = report.positionsOnly.count
            let poNote = po > 0 ? " (\(po) positions-only)" : ""
            return "Restored '\(name)': \(report.moved.count) moved, \(report.failures.count) failed\(poNote)"
        } else {
            let report = nativeRestorer.restore(snapshot)
            return "Restored '\(name)' (native): \(report.moved.count) repositioned, \(report.failures.count) skipped"
        }
    }

    func restoreAuto() async throws -> String {
        guard availability.isAvailable() else {
            return "Auto-restore needs yabai. Click a saved layout to restore it."
        }
        let displays = try yabai.queryDisplays()
        let snapshots = try store.loadAll()
        switch autoSelector.select(from: snapshots, currentDisplays: displays) {
        case let .confident(scored):
            let report = try restorer.restore(scored.snapshot)
            return "Restored '\(scored.snapshot.name)': \(report.moved.count) moved, \(report.failures.count) failed"
        case let .ambiguous(candidates):
            let names = candidates.map(\.snapshot.name).joined(separator: ", ")
            return "Ambiguous — pick manually. Candidates: \(names)"
        case .none:
            return "No snapshot matches the current displays"
        }
    }
}
