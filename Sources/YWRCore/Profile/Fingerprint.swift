import Foundation

/// Produces a stable, human-readable identifier for a display configuration.
/// Abstracted so the fingerprinting rule can evolve (Open/Closed) without
/// touching capture/restore.
public protocol FingerprintGenerating: Sendable {
    func fingerprint(for displays: [Display]) -> String
}

/// Default fingerprint: displays sorted left-to-right, each rendered as
/// `<width>x<height>`, joined by `+`. e.g. `1728x1117+3840x2160`.
///
/// Deliberately geometry-based rather than uuid-based so two machines with the
/// same physical layout share a fingerprint; precise uuid/serial matching is
/// handled separately by `DisplayMatcher` during restore.
public struct DefaultFingerprintGenerator: FingerprintGenerating {
    public init() {}

    public func fingerprint(for displays: [Display]) -> String {
        displays
            .sorted { $0.frame.x < $1.frame.x }
            .map { "\(Int($0.frame.w.rounded()))x\(Int($0.frame.h.rounded()))" }
            .joined(separator: "+")
    }
}
