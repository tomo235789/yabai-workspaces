import Foundation
import YWRCore

struct RestoreCommand: Command {
    let name = "restore"
    let summary = "Restore a saved layout (use --dry-run to preview, --auto to pick)"
    var usage: String { "ywr restore <name>|--auto [--dry-run] [--create-spaces] [--positions-only] [--native]" }

    private let store: SnapshotStore
    private let restorer: SnapshotRestorer
    private let nativeRestorer: NativeRestorer
    private let availability: YabaiAvailabilityChecking
    private let yabai: YabaiQuerying
    private let autoSelector: AutoSelector

    init(store: SnapshotStore, restorer: SnapshotRestorer, nativeRestorer: NativeRestorer, availability: YabaiAvailabilityChecking, yabai: YabaiQuerying, autoSelector: AutoSelector = AutoSelector()) {
        self.store = store
        self.restorer = restorer
        self.nativeRestorer = nativeRestorer
        self.availability = availability
        self.yabai = yabai
        self.autoSelector = autoSelector
    }

    func run(_ args: [String]) throws -> Int32 {
        let dryRun = args.contains("--dry-run")
        let auto = args.contains("--auto")
        let createSpaces = args.contains("--create-spaces")
        let positionsOnly = args.contains("--positions-only")
        let nativeFlag = args.contains("--native")
        let yabaiDown = !availability.isAvailable()

        if createSpaces && positionsOnly {
            throw CLIError.message("--create-spaces cannot be combined with --positions-only (positions-only does not touch Spaces).")
        }

        // --auto needs the yabai backend (it matches on display fingerprints).
        if auto {
            if nativeFlag || yabaiDown {
                throw CLIError.message("--auto requires the yabai backend (needs display fingerprints).")
            }
            guard let selected = try resolveAuto() else { return 1 }
            if dryRun {
                return try previewPlan(for: selected, createSpaces: createSpaces, positionsOnly: positionsOnly)
            }
            return try executeRestore(selected, createSpaces: createSpaces, positionsOnly: positionsOnly)
        }

        // Restore by name.
        let positional = args.filter { !$0.hasPrefix("--") }
        guard let snapName = positional.first else {
            throw CLIError.usage(usage)
        }
        let snapshot: Snapshot
        do { snapshot = try store.load(name: snapName) } catch { throw CLIError.message("\(error)") }

        // Use the native backend when forced (--native), when yabai isn't
        // running, OR when the snapshot itself is native — a native snapshot's
        // zeroed geometry can't go through the yabai planner.
        let snapshotIsNative = snapshot.displayProfile.fingerprint == NativeCapturer.nativeFingerprint
        if nativeFlag || yabaiDown || snapshotIsNative {
            if createSpaces { throw CLIError.message("--create-spaces requires the yabai backend.") }
            return nativeRestore(snapshot, dryRun: dryRun)
        }

        if dryRun {
            return try previewPlan(for: snapshot, createSpaces: createSpaces, positionsOnly: positionsOnly)
        }
        return try executeRestore(snapshot, createSpaces: createSpaces, positionsOnly: positionsOnly)
    }

    /// Geometry-only restore through the yabai-independent Accessibility backend.
    private func nativeRestore(_ snapshot: Snapshot, dryRun: Bool) -> Int32 {
        print("Native backend (yabai-independent): geometry-only restore.")
        if dryRun {
            print("Dry run for '\(snapshot.name)' — \(snapshot.windows.count) saved window(s) would be considered for app+title matching against live windows (unmatched ones are skipped).")
            print("No changes made (dry run).")
            return 0
        }
        let report = nativeRestorer.restore(snapshot)
        print("Restored '\(snapshot.name)': \(report.moved.count) window(s) repositioned.")
        guard !report.failures.isEmpty else { return 0 }
        print("\n\(report.failures.count) window(s) could not be restored:")
        for o in report.failures {
            switch o.status {
            case .unmatched: print("  • \(o.label): no matching window found")
            case let .failed(reason): print("  • \(o.label): \(reason)")
            default: break
            }
        }
        return 1
    }

    /// Uses gemma-authored `AutoSelector` to pick the snapshot matching the
    /// current displays. Returns nil (with a printed reason) when there's no
    /// confident choice.
    private func resolveAuto() throws -> Snapshot? {
        let displays = try yabai.queryDisplays()
        let snapshots = try store.loadAll()
        switch autoSelector.select(from: snapshots, currentDisplays: displays) {
        case let .confident(scored):
            print("Auto-selected '\(scored.snapshot.name)' (match score \(scored.score))")
            return scored.snapshot
        case let .ambiguous(candidates):
            print("Ambiguous — no single close match. Candidates:")
            for c in candidates {
                print("  • \(c.snapshot.name) (score \(c.score), \(c.snapshot.displayProfile.fingerprint))")
            }
            print("\nRe-run with an explicit name: ywr restore <name>")
            return nil
        case .none:
            print("No snapshots to choose from. Create one with `ywr snapshot save <name>`.")
            return nil
        }
    }

    private func previewPlan(for snapshot: Snapshot, createSpaces: Bool, positionsOnly: Bool) throws -> Int32 {
        let plan = try restorer.buildPlan(for: snapshot)
        print("Dry run for '\(snapshot.name)' (\(snapshot.displayProfile.fingerprint))\n")

        if snapshot.spaceMode == .unifiedDesktop {
            // The real restore visits every virtual desktop to find windows, but
            // dry-run must not switch desktops — so this preview only reflects the
            // CURRENT desktop and may over-report launches/unmatched windows.
            print("Note: unified-desktop snapshot — this preview only sees the current desktop.")
            print("Windows on other virtual desktops may show as \"will launch\"/unmatched but will be found on the real restore.\n")
        }
        if positionsOnly {
            print("Positions-only: Display/Space moves will be skipped; only window geometry is restored.\n")
        }
        if createSpaces && !positionsOnly {
            let requests = try restorer.provisionRequests(for: snapshot)
            if requests.isEmpty {
                print("Spaces to create: none\n")
            } else {
                print("Spaces to create:")
                for r in requests { print("  • display \(r.displayIndex) → label \"\(r.label)\"") }
                print("")
            }
        }
        if !plan.appsToLaunch.isEmpty {
            print("Apps to launch:")
            for app in plan.appsToLaunch { print("  • \(app)") }
            print("")
        }
        if !plan.spaceLabels.isEmpty {
            print("Space labels to apply:")
            for label in plan.spaceLabels { print("  • space \(label.spaceIndex) → \"\(label.label)\"") }
            print("")
        }
        print("Window moves:")
        for step in plan.steps {
            let target = "display \(step.targetDisplayIndex), space \(step.targetSpaceIndex)"
            let geom = step.shouldFloat
                ? String(format: " @ (%.0f,%.0f %.0f×%.0f)", step.targetFrame.x, step.targetFrame.y, step.targetFrame.w, step.targetFrame.h)
                : " (managed)"
            let matched = step.matchedWindowId == nil ? " [will launch]" : ""
            print("  • \(step.describedLabel) → \(target)\(geom)\(matched)")
        }
        if !plan.unmatched.isEmpty {
            print("\nUnmatched (running but not identified):")
            for w in plan.unmatched {
                print("  • \(w.app) — \(w.title.isEmpty ? "(untitled)" : w.title)")
            }
        }
        print("\nNo changes made (dry run).")
        return 0
    }

    private func executeRestore(_ snapshot: Snapshot, createSpaces: Bool, positionsOnly: Bool) throws -> Int32 {
        let report = try restorer.restore(snapshot, createSpaces: createSpaces, positionsOnly: positionsOnly)
        let poCount = report.positionsOnly.count
        let poNote = poCount > 0 ? " (\(poCount) positions-only)" : ""
        print("Restored '\(snapshot.name)': \(report.moved.count) window(s) moved\(poNote).")

        if !positionsOnly && poCount > 0 {
            print("Note: \(poCount) window(s) kept their current Space — Display/Space move was unavailable " +
                  "(enable 'Displays have separate Spaces' + the yabai scripting addition for full restore).")
        }
        if report.failures.isEmpty {
            return 0
        }
        // Surface every failure at the end — never swallow silently (P0-6).
        print("\n\(report.failures.count) window(s) could not be restored:")
        for outcome in report.failures {
            switch outcome.status {
            case .unmatched:
                print("  • \(outcome.label): no matching window found")
            case let .failed(reason):
                print("  • \(outcome.label): \(reason)")
            default:
                break
            }
        }
        return 1
    }
}
