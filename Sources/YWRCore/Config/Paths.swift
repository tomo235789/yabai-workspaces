import Foundation

/// Resolves on-disk locations. Kept as its own type so path policy lives in one
/// place and tests can point it at a temp directory.
public struct Paths: Sendable {
    public let root: URL

    /// Honors `XDG_CONFIG_HOME`, falling back to `~/.config`.
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let base: URL = if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config", isDirectory: true)
        }
        root = base.appendingPathComponent("yabai-workspaces", isDirectory: true)
    }

    public init(root: URL) {
        self.root = root
    }

    public var snapshotsDir: URL {
        root.appendingPathComponent("snapshots", isDirectory: true)
    }

    public var profilesDir: URL {
        root.appendingPathComponent("profiles", isDirectory: true)
    }

    public func snapshotFile(name: String) -> URL {
        snapshotsDir.appendingPathComponent("\(name).json")
    }

    public func profileFile(name: String) -> URL {
        profilesDir.appendingPathComponent("\(name).json")
    }

    /// Where a Pro license (if any) lives. A signed license dropped here lifts
    /// the free-tier limits; absent/invalid means the free tier.
    public var licenseFile: URL {
        root.appendingPathComponent("license.json")
    }

    /// A snapshot/profile name must be a single, safe path component — reject
    /// anything with path separators, `..`, NUL, or leading dots so a name can
    /// never escape `snapshotsDir` / `profilesDir` (path traversal).
    public static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 200 else { return false }
        guard !name.contains("/"), !name.contains("\\"), !name.contains("\0") else { return false }
        guard !name.hasPrefix(".") else { return false } // rules out "." and ".."
        return true
    }
}

public enum NameError: Error, CustomStringConvertible {
    case invalid(String)

    public var description: String {
        "invalid name '\(name)': use a single word without '/', '\\', or a leading '.'"
    }

    private var name: String {
        if case let .invalid(n) = self {
            return n
        }
        return ""
    }
}
