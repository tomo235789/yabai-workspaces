import Foundation
import YWRCore

// Implemented via ollama gemma4:31b, reviewed and integrated unchanged.

struct ProfileCommand: Command {
    let name = "profile"
    let summary = "Capture or list display profiles"
    var usage: String { "ywr profile <capture|list> [name]" }

    private let capturer: ProfileCapturing
    private let store: ProfileStore

    init(capturer: ProfileCapturing, store: ProfileStore) {
        self.capturer = capturer
        self.store = store
    }

    func run(_ args: [String]) throws -> Int32 {
        guard let subcommand = args.first else {
            throw CLIError.usage(usage)
        }

        switch subcommand {
        case "capture":
            guard args.count > 1 else {
                throw CLIError.usage("ywr profile capture <name>")
            }
            let profileName = args[1]
            let captured = try capturer.capture(name: profileName, at: Date())
            try store.save(captured)

            print("Captured profile '\(profileName)': \(captured.profile.displays.count) display(s)")
            print("Fingerprint: \(captured.profile.fingerprint)")
            return 0

        case "list":
            let profiles = try store.list()
            if profiles.isEmpty {
                print("No profiles captured yet. Create one with `ywr profile capture <name>`.")
                return 0
            }

            let formatter = ISO8601DateFormatter()
            for p in profiles {
                let dateString = formatter.string(from: p.capturedAt)
                print("\(p.name) | \(p.profile.fingerprint) | Displays: \(p.profile.displays.count) | Captured: \(dateString)")
            }
            return 0

        default:
            throw CLIError.usage(usage)
        }
    }
}
