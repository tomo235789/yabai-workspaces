import Foundation

// Implemented via ollama gemma4:31b, reviewed and integrated with one fix:
//   - use "\(error)" instead of error.localizedDescription, since the project's
//     error types conform to CustomStringConvertible (not LocalizedError) and
//     localizedDescription would yield a generic Cocoa message.

/// Reacts to a display-configuration change by auto-restoring the best-matching
/// snapshot. The restore action is injected as a closure so this handler is
/// decoupled from `SnapshotRestorer` and easy to test.
public struct AutoRestoreHandler: DisplayChangeHandling {
    private let yabai: YabaiQuerying
    private let store: any SnapshotStore
    private let selector: AutoSelector
    private let restoreAction: (Snapshot) throws -> RestoreReport
    private let logger: any EventLogging

    public init(
        yabai: YabaiQuerying,
        store: SnapshotStore,
        selector: AutoSelector = AutoSelector(),
        restore: @escaping (Snapshot) throws -> RestoreReport,
        logger: EventLogging = ConsoleLogger()
    ) {
        self.yabai = yabai
        self.store = store
        self.selector = selector
        self.restoreAction = restore
        self.logger = logger
    }

    public func handleChange(from oldFingerprint: String?, to newFingerprint: String) {
        logger.log("Display configuration changed: \(oldFingerprint ?? "none") -> \(newFingerprint)")

        do {
            let currentDisplays = try yabai.queryDisplays()
            let snapshots = try store.loadAll()

            switch selector.select(from: snapshots, currentDisplays: currentDisplays) {
            case .confident(let scored):
                logger.log("Auto-restoring '\(scored.snapshot.name)' (score \(scored.score))")
                do {
                    let report = try restoreAction(scored.snapshot)
                    logger.log("Restore complete: \(report.moved.count) moved, \(report.failures.count) failed")
                } catch {
                    logger.log("Restore failed: \(error)")
                }

            case .ambiguous(let candidates):
                let candidateList = candidates
                    .map { "\($0.snapshot.name)(\($0.score))" }
                    .joined(separator: ", ")
                logger.log("Ambiguous match; skipping auto-restore. Candidates: \(candidateList)")

            case .none:
                logger.log("No snapshots to restore for this configuration.")
            }
        } catch {
            logger.log("Error during auto-restore process: \(error)")
        }
    }
}
