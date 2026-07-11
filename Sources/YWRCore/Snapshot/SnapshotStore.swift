import Foundation

/// Lightweight summary for `snapshot list` without decoding every window.
public struct SnapshotSummary: Sendable {
    public let name: String
    public let fingerprint: String
    public let capturedAt: Date
    public let windowCount: Int
    public let spaceCount: Int

    public init(name: String, fingerprint: String, capturedAt: Date, windowCount: Int, spaceCount: Int) {
        self.name = name
        self.fingerprint = fingerprint
        self.capturedAt = capturedAt
        self.windowCount = windowCount
        self.spaceCount = spaceCount
    }
}

/// Persistence boundary for snapshots. An abstraction so restore/list logic can
/// be tested against an in-memory store and a future backend (iCloud, etc.)
/// can be swapped in without touching callers. Not `Sendable`: it wraps
/// `FileManager`/coders and is only ever used from the single CLI thread.
public protocol SnapshotStore {
    func save(_ snapshot: Snapshot) throws
    func load(name: String) throws -> Snapshot
    func list() throws -> [SnapshotSummary]
    /// Full snapshots, needed by `restore --auto` to score every candidate.
    func loadAll() throws -> [Snapshot]
    func exists(name: String) -> Bool
}

public enum SnapshotStoreError: Error, CustomStringConvertible {
    case notFound(name: String)

    public var description: String {
        switch self {
        case let .notFound(name):
            return "snapshot '\(name)' not found"
        }
    }
}

/// JSON-file-backed store under `Paths.snapshotsDir`.
public struct FileSnapshotStore: SnapshotStore {
    private let paths: Paths
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(paths: Paths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func save(_ snapshot: Snapshot) throws {
        guard Paths.isValidName(snapshot.name) else { throw NameError.invalid(snapshot.name) }
        try fileManager.createDirectory(at: paths.snapshotsDir, withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        try data.write(to: paths.snapshotFile(name: snapshot.name), options: .atomic)
    }

    public func load(name: String) throws -> Snapshot {
        guard Paths.isValidName(name) else { throw NameError.invalid(name) }
        let url = paths.snapshotFile(name: name)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SnapshotStoreError.notFound(name: name)
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(Snapshot.self, from: data)
    }

    public func exists(name: String) -> Bool {
        guard Paths.isValidName(name) else { return false }
        return fileManager.fileExists(atPath: paths.snapshotFile(name: name).path)
    }

    public func list() throws -> [SnapshotSummary] {
        try loadAll().map { snap in
            SnapshotSummary(
                name: snap.name,
                fingerprint: snap.displayProfile.fingerprint,
                capturedAt: snap.capturedAt,
                windowCount: snap.windows.count,
                spaceCount: snap.spaces.count
            )
        }
    }

    public func loadAll() throws -> [Snapshot] {
        guard fileManager.fileExists(atPath: paths.snapshotsDir.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(at: paths.snapshotsDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(Snapshot.self, from: data)
        }
        .sorted { $0.capturedAt > $1.capturedAt }
    }
}
