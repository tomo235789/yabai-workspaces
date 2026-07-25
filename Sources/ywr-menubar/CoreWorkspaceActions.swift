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
        let snapshot = try capturer.capture(name: name, at: Date())
        try store.save(snapshot)
    }

    func restore(name: String) async throws -> String {
        let snapshot = try store.load(name: name)
        let report = try restorer.restore(snapshot)
        let po = report.positionsOnly.count
        let poNote = po > 0 ? " (\(po) positions-only)" : ""
        return "Restored '\(name)': \(report.moved.count) moved, \(report.failures.count) failed\(poNote)"
    }

    func restoreAuto() async throws -> String {
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
