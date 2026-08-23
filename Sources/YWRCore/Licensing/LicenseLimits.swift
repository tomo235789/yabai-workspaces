/// Free-tier limits. Pro entitlements lift them.
public enum LicenseLimits {
    /// How many snapshots the free tier may keep. `ProFeature.unlimitedSnapshots`
    /// removes the cap.
    public static let freeSnapshotLimit = 3
}

/// Thrown when a free-tier action hits its limit. Its description is a
/// user-facing message.
public struct FreeTierLimitError: Error, CustomStringConvertible {
    public init() {}
    public var description: String {
        "Free tier is limited to \(LicenseLimits.freeSnapshotLimit) snapshots — "
            + "delete one, or unlock Pro for unlimited."
    }
}

public extension LicenseGate {
    /// Whether a brand-new snapshot may be saved, given how many already exist.
    /// Overwriting an existing name doesn't grow the count, so callers should
    /// only apply this to genuinely new names.
    func canSaveNewSnapshot(existingCount: Int) -> Bool {
        isEntitled(to: .unlimitedSnapshots) || existingCount < LicenseLimits.freeSnapshotLimit
    }
}
