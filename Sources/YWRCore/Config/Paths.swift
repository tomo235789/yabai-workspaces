import Foundation

/// Resolves on-disk locations. Kept as its own type so path policy lives in one
/// place and tests can point it at a temp directory.
public struct Paths: Sendable {
    public let root: URL

    /// Honors `XDG_CONFIG_HOME`, falling back to `~/.config`.
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let base: URL
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config", isDirectory: true)
        }
        self.root = base.appendingPathComponent("yabai-workspaces", isDirectory: true)
    }

    public init(root: URL) {
        self.root = root
    }

    public var snapshotsDir: URL { root.appendingPathComponent("snapshots", isDirectory: true) }
    public var profilesDir: URL { root.appendingPathComponent("profiles", isDirectory: true) }

    public func snapshotFile(name: String) -> URL {
        snapshotsDir.appendingPathComponent("\(name).json")
    }

    public func profileFile(name: String) -> URL {
        profilesDir.appendingPathComponent("\(name).json")
    }
}
