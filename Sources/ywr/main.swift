import Foundation
import YWRCore

// Composition root: the one place concrete implementations are chosen and wired
// together. Everything below this line depends only on abstractions.

let runner = ProcessCommandRunner()
let yabai = YabaiClient(runner: runner)
let paths = Paths()

let store = FileSnapshotStore(paths: paths)
let spaceModeDetector = MacOSSpaceModeDetector(runner: runner)
let capturer = SnapshotCapturer(yabai: yabai, spaceModeDetector: spaceModeDetector)
let launcher = AppLauncher(runner: runner)
let restorer = SnapshotRestorer(yabai: yabai, launcher: launcher)

let profileStore = FileProfileStore(paths: paths)
let profileCapturer = ProfileCapturer(yabai: yabai)

// Native (yabai-independent) backend for configurations where yabai can't run.
let availability = YabaiAvailability(runner: runner)
let nativeEnumerator = CGWindowEnumerator()
let nativeController = AXWindowController()
let nativeCapturer = NativeCapturer(enumerator: nativeEnumerator)
let nativeRestorer = NativeRestorer(enumerator: nativeEnumerator, controller: nativeController)
// Experimental multi-desktop restore: walks Spaces so windows on other desktops
// are repositioned too (opt-in via `restore --walk-spaces`).
let nativeWalker = WalkingNativeRestorer(enumerator: nativeEnumerator, controller: nativeController)

let doctor = Doctor(checks: [
    YabaiInstalledCheck(runner: runner),
    YabaiQueryableCheck(yabai: yabai),
    ActiveBackendCheck(availability: availability),
    MacOSSettingsNoticeCheck(),
])

// Daemon: watch for display changes and auto-restore. The handler restores via
// the shared `restorer`; the monitor's poll interval is supplied per-invocation.
let autoRestoreHandler = AutoRestoreHandler(
    yabai: yabai,
    store: store,
    restore: { try restorer.restore($0) }
)
let daemonFactory: (Double) -> DisplayMonitor = { interval in
    DisplayMonitor(
        watcher: DisplayWatcher(yabai: yabai),
        handler: autoRestoreHandler,
        pollInterval: interval
    )
}

// Signal integration: yabai runs THIS binary's `restore --auto` on display
// events. Resolve an absolute path so the action works regardless of yabai's PATH.
let ywrPath = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
let signalInstaller = SignalInstaller(runner: runner, ywrInvocation: "\(ywrPath) restore --auto")

let registry = CommandRegistry(commands: [
    DoctorCommand(doctor: doctor),
    SnapshotCommand(capturer: capturer, nativeCapturer: nativeCapturer, availability: availability, store: store),
    RestoreCommand(store: store, restorer: restorer, nativeRestorer: nativeRestorer, nativeWalker: nativeWalker, availability: availability, yabai: yabai),
    ProfileCommand(capturer: profileCapturer, store: profileStore),
    DaemonCommand(monitorFactory: daemonFactory),
    SignalCommand(installer: signalInstaller),
])

let exitCode = registry.run(Array(CommandLine.arguments.dropFirst()))
exit(exitCode)
