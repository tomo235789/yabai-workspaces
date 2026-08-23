/// The seam a private, commercial "Pro" module conforms to, supplying paid
/// features on top of the open-source core. The open-source build has no
/// provider (nil) and falls back to the free gate, so its behavior is identical
/// without it.
///
/// Pro capability factories are added to this protocol as features are built
/// (e.g. a display-change auto-restore controller), keeping the core unaware of
/// their implementations — Dependency Inversion across the open/closed boundary.
public protocol ProProvider: Sendable {
    var licenseGate: LicenseGate { get }
}

/// The active gate: the Pro provider's gate when a Pro module is present,
/// otherwise the free gate. Composition roots call this once and inject the
/// result wherever a Pro-only path is guarded.
public func resolveLicenseGate(_ provider: ProProvider?) -> LicenseGate {
    provider?.licenseGate ?? FreeLicenseGate()
}
