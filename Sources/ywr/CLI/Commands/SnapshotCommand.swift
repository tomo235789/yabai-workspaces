import Foundation
import YWRCore

/// `snapshot` groups the save/list subcommands. Dispatch mirrors the top-level
/// registry so behavior stays consistent.
struct SnapshotCommand: Command {
    let name = "snapshot"
    let summary = "Save, list, or delete layout snapshots"
    var usage: String {
        "ywr snapshot save <name> [--native] | ywr snapshot list | ywr snapshot delete <name>"
    }

    private let capturer: SnapshotCapturing
    private let nativeCapturer: NativeCapturer
    private let availability: YabaiAvailabilityChecking
    private let store: SnapshotStore

    init(capturer: SnapshotCapturing, nativeCapturer: NativeCapturer, availability: YabaiAvailabilityChecking, store: SnapshotStore) {
        self.capturer = capturer
        self.nativeCapturer = nativeCapturer
        self.availability = availability
        self.store = store
    }

    func run(_ args: [String]) throws -> Int32 {
        guard let sub = args.first else {
            throw CLIError.usage(usage)
        }
        let rest = Array(args.dropFirst())
        switch sub {
        case "save": return try save(rest)
        case "list": return try list(rest)
        case "delete": return try delete(rest)
        default: throw CLIError.usage(usage)
        }
    }

    private func delete(_ args: [String]) throws -> Int32 {
        // Exactly one positional name, no flags — reject extras so a typo like
        // `snapshot delete home extar` fails loudly instead of deleting `home`.
        guard args.count == 1, let snapName = args.first, !snapName.hasPrefix("--") else {
            throw CLIError.usage("ywr snapshot delete <name>")
        }
        try store.delete(name: snapName)
        print("Deleted snapshot '\(snapName)'")
        return 0
    }

    private func save(_ args: [String]) throws -> Int32 {
        guard let snapName = args.first(where: { !$0.hasPrefix("--") }) else {
            throw CLIError.usage("ywr snapshot save <name> [--native]")
        }
        // Use the yabai-independent backend when asked (--native) or when yabai
        // isn't available (e.g. "Displays have separate Spaces" is off).
        let useNative = args.contains("--native") || !availability.isAvailable()
        let snapshot: Snapshot
        if useNative {
            print("Using native backend (yabai unavailable or --native): geometry-only capture.")
            snapshot = nativeCapturer.capture(name: snapName, at: Date())
        } else {
            snapshot = try capturer.capture(name: snapName, at: Date())
        }
        try store.save(snapshot)
        print("Saved snapshot '\(snapName)': \(snapshot.windows.count) window(s), \(snapshot.spaces.count) space(s)")
        print("Display profile: \(snapshot.displayProfile.fingerprint)")
        print("Space mode: \(snapshot.spaceMode.rawValue)")
        return 0
    }

    private func list(_ args: [String]) throws -> Int32 {
        let summaries = try store.list()
        guard !summaries.isEmpty else {
            print("No snapshots saved yet. Create one with `ywr snapshot save <name>`.")
            return 0
        }
        let formatter = ISO8601DateFormatter()
        let nameWidth = max(4, summaries.map(\.name.count).max() ?? 4)
        let fpWidth = max(7, summaries.map(\.fingerprint.count).max() ?? 7)
        let header = "\("NAME".padding(toLength: nameWidth, withPad: " ", startingAt: 0))  "
            + "\("PROFILE".padding(toLength: fpWidth, withPad: " ", startingAt: 0))  "
            + "WINDOWS  SPACES  CAPTURED"
        print(header)
        for s in summaries {
            let line = "\(s.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0))  "
                + "\(s.fingerprint.padding(toLength: fpWidth, withPad: " ", startingAt: 0))  "
                + "\(String(s.windowCount).padding(toLength: 7, withPad: " ", startingAt: 0))  "
                + "\(String(s.spaceCount).padding(toLength: 6, withPad: " ", startingAt: 0))  "
                + formatter.string(from: s.capturedAt)
            print(line)
        }
        return 0
    }
}
