import Foundation
import YWRCore

/// `signal` registers yabai signals so yabai runs `ywr restore --auto` on
/// display changes — an event-driven alternative to `ywr daemon`.
struct SignalCommand: Command {
    let name = "signal"
    let summary = "Install/remove yabai signals for auto-restore on display changes"
    var usage: String { "ywr signal <install|uninstall|list>" }

    private let installer: SignalInstaller

    init(installer: SignalInstaller) {
        self.installer = installer
    }

    func run(_ args: [String]) throws -> Int32 {
        guard let sub = args.first else {
            throw CLIError.usage(usage)
        }
        switch sub {
        case "install":
            try installer.install()
            print("Installed \(installer.definitions.count) yabai signal(s):")
            for d in installer.definitions { print("  • \(d.event) → \(d.label)") }
            return 0
        case "uninstall":
            let errors = installer.uninstall()
            print("Removed ywr signals (\(installer.installedLabels().joined(separator: ", ")))")
            if !errors.isEmpty {
                // Best-effort cleanup: surface issues as warnings but don't fail.
                print("Warnings (\(errors.count)):")
                for e in errors { print("  • \(e)") }
            }
            return 0
        case "list":
            print("ywr signals:")
            for d in installer.definitions { print("  • \(d.event) → \(d.label)") }
            return 0
        default:
            throw CLIError.usage(usage)
        }
    }
}
