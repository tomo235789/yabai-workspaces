import Foundation

// Implemented via ollama gemma4:31b, then reviewed and adjusted:
//   - list(): guard against a missing profiles directory (return []).
//   - save(): atomic write, matching FileSnapshotStore.

public struct CapturedProfile: Codable, Equatable, Sendable {
    public var version: Int
    public var name: String
    public var capturedAt: Date
    public var profile: DisplayProfile

    public init(version: Int = 1, name: String, capturedAt: Date, profile: DisplayProfile) {
        self.version = version
        self.name = name
        self.capturedAt = capturedAt
        self.profile = profile
    }
}

public protocol ProfileStore {
    func save(_ profile: CapturedProfile) throws
    func load(name: String) throws -> CapturedProfile
    func list() throws -> [CapturedProfile]
    func exists(name: String) -> Bool
}

public enum ProfileStoreError: Error, CustomStringConvertible {
    case notFound(name: String)

    public var description: String {
        switch self {
        case .notFound(let name):
            return "profile '\(name)' not found"
        }
    }
}

public struct FileProfileStore: ProfileStore {
    private let paths: Paths
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(paths: Paths) {
        self.paths = paths

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func save(_ profile: CapturedProfile) throws {
        let url = paths.profileFile(name: profile.name)
        try FileManager.default.createDirectory(at: paths.profilesDir, withIntermediateDirectories: true)
        let data = try encoder.encode(profile)
        try data.write(to: url, options: .atomic)
    }

    public func load(name: String) throws -> CapturedProfile {
        let url = paths.profileFile(name: name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProfileStoreError.notFound(name: name)
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(CapturedProfile.self, from: data)
    }

    public func list() throws -> [CapturedProfile] {
        guard FileManager.default.fileExists(atPath: paths.profilesDir.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: paths.profilesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let profiles = files.compactMap { url -> CapturedProfile? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(CapturedProfile.self, from: data)
        }
        return profiles.sorted { $0.capturedAt > $1.capturedAt }
    }

    public func exists(name: String) -> Bool {
        FileManager.default.fileExists(atPath: paths.profileFile(name: name).path)
    }
}

public protocol ProfileCapturing: Sendable {
    func capture(name: String, at date: Date) throws -> CapturedProfile
}

public struct ProfileCapturer: ProfileCapturing {
    private let yabai: YabaiQuerying
    private let fingerprintGenerator: FingerprintGenerating

    public init(yabai: YabaiQuerying, fingerprint: FingerprintGenerating = DefaultFingerprintGenerator()) {
        self.yabai = yabai
        self.fingerprintGenerator = fingerprint
    }

    public func capture(name: String, at date: Date) throws -> CapturedProfile {
        let displays = try yabai.queryDisplays()
        let fp = fingerprintGenerator.fingerprint(for: displays)
        let profile = DisplayProfile(fingerprint: fp, displays: displays)
        return CapturedProfile(name: name, capturedAt: date, profile: profile)
    }
}
