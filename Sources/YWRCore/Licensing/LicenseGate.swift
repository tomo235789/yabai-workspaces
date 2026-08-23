// Licensing seam for the open-core model. The open-source build ships
// `FreeLicenseGate` (everything is the free tier); a separate, commercial Pro
// build injects a real gate via `ProProvider`. Defining these types in the open
// core lets Pro features plug in later without changing the free build.

public enum Tier: String, Sendable, Equatable, CaseIterable, Codable {
    case free
    case pro
}

/// Commercial features gated behind a Pro license. Naming them here (in the open
/// core) fixes the gate points; the implementations live in the separate Pro
/// module. The free build entitles none of them.
public enum ProFeature: String, Sendable, Equatable, CaseIterable {
    /// Auto-apply a saved layout when the display setup changes (dock/undock).
    case autoRestore
    /// The free tier caps how many layouts you can save; Pro lifts the cap.
    case unlimitedSnapshots
    /// Sync saved layouts across Macs.
    case cloudSync
}

/// Decides the current tier and per-feature entitlement. Consumers ask
/// `isEntitled(to:)` before running a Pro-only path.
public protocol LicenseGate: Sendable {
    var tier: Tier { get }
    func isEntitled(to feature: ProFeature) -> Bool
}

public extension LicenseGate {
    /// Default all-or-nothing entitlement: every Pro feature is unlocked at the
    /// Pro tier. A gate with per-feature rules can override this.
    func isEntitled(to _: ProFeature) -> Bool {
        tier == .pro
    }
}

/// The gate the open-source build uses: always the free tier, no Pro features.
public struct FreeLicenseGate: LicenseGate {
    public init() {}
    public var tier: Tier {
        .free
    }
}
