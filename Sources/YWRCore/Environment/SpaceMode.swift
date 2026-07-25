import Foundation

public enum SpaceMode: String, Codable, Equatable, Sendable {
    case separatePerDisplay
    case unifiedDesktop
    case unknown
}

public protocol SpaceModeDetecting: Sendable {
    func detect() -> SpaceMode
}

public struct MacOSSpaceModeDetector: SpaceModeDetecting {
    private let runner: CommandRunner

    public init(runner: CommandRunner) { self.runner = runner }

    public func detect() -> SpaceMode {
        guard let result = try? runner.run("defaults", ["read", "com.apple.spaces", "spans-displays"]),
              result.succeeded else { return .unknown }
        switch result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes": return .unifiedDesktop
        case "0", "false", "no": return .separatePerDisplay
        default: return .unknown
        }
    }
}

public struct FixedSpaceModeDetector: SpaceModeDetecting {
    private let mode: SpaceMode
    public init(_ mode: SpaceMode) { self.mode = mode }
    public func detect() -> SpaceMode { mode }
}
