import Foundation
import YWRCore

// Composition root: the one place concrete implementations are chosen and wired
// together. Everything below this line depends only on abstractions.

let runner = ProcessCommandRunner()
let yabai = YabaiClient(runner: runner)
let paths = Paths()

let store = FileSnapshotStore(paths: paths)
// Licensing: a valid Pro license at paths.licenseFile lifts free-tier limits;
// otherwise the free gate applies. Verified offline (no network).
let licenseGate = LicenseLoader.gate(licenseFileURL: paths.licenseFile)
let spaceModeDetector = MacOSSpaceModeDetector(runner: runner)
let capturer = SnapshotCapturer(yabai: yabai, spaceModeDetector: spaceModeDetector)
let launcher = AppLauncher(runner: runner)
let restorer = SnapshotRestorer(yabai: yabai, launcher: launcher)

let profileStore = FileProfileStore(paths: paths)
let profileCapturer = ProfileCapturer(yabai: yabai)

/// Native (yabai-independent) backend for configurations where yabai can't run.
let availability = YabaiAvailability(runner: runner)

/// One-time migration: earlier versions could register yabai signals that ran the
/// now-removed `restore --auto` on display changes. When yabai is reachable, remove
/// any such stale registrations (best-effort; a missing label is fine) and record
/// that cleanup is done. If yabai is down we skip WITHOUT marking and retry on a
/// later run — stale signals only fire while yabai runs, so deferring is harmless.
/// The marker check short-circuits before the availability probe once migrated.
let signalsMigratedMarker = paths.root.appendingPathComponent(".signals-migrated")
/// Which of our signal labels yabai still has registered. Returns nil when yabai's
/// signal list can't be read (transient failure) so we defer rather than guess.
let remainingYWRSignals: () -> [String]? = {
    let labels = ["ywr_display_added", "ywr_display_removed", "ywr_display_moved"]
    guard let result = try? runner.run("yabai", ["-m", "signal", "--list"]), result.succeeded,
          let data = result.stdout.data(using: .utf8),
          let entries = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    else {
        return nil
    }
    let registered = entries.compactMap { $0["label"] as? String }
    return labels.filter(registered.contains)
}

if !FileManager.default.fileExists(atPath: signalsMigratedMarker.path), availability.isAvailable() {
    if let remaining = remainingYWRSignals() {
        for label in remaining {
            _ = try? runner.run("yabai", ["-m", "signal", "--remove", label])
        }
        // Record success only once every stale signal is confirmed gone, so a
        // transient removal failure is retried on a later run instead of skipped.
        if remainingYWRSignals()?.isEmpty == true {
            try? FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: signalsMigratedMarker.path, contents: nil)
        }
    }
}

let nativeEnumerator = CGWindowEnumerator()
let nativeController = AXWindowController()
let nativeCapturer = NativeCapturer(enumerator: nativeEnumerator)
let nativeRestorer = NativeRestorer(enumerator: nativeEnumerator, controller: nativeController)
/// Experimental multi-desktop restore: walks Spaces so windows on other desktops
/// are repositioned too (opt-in via `restore --walk-spaces`).
let nativeWalker = WalkingNativeRestorer(enumerator: nativeEnumerator, controller: nativeController)

let doctor = Doctor(checks: [
    YabaiInstalledCheck(runner: runner),
    YabaiQueryableCheck(yabai: yabai),
    ActiveBackendCheck(availability: availability),
    MacOSSettingsNoticeCheck(),
])

let registry = CommandRegistry(commands: [
    DoctorCommand(doctor: doctor),
    SnapshotCommand(capturer: capturer, nativeCapturer: nativeCapturer, availability: availability, store: store, licenseGate: licenseGate),
    RestoreCommand(store: store, restorer: restorer, nativeRestorer: nativeRestorer, nativeWalker: nativeWalker, availability: availability),
    ProfileCommand(capturer: profileCapturer, store: profileStore),
])

let exitCode = registry.run(Array(CommandLine.arguments.dropFirst()))
exit(exitCode)
