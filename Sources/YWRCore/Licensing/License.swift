import CryptoKit
import Foundation

/// A Pro license. Signed offline with an Ed25519 private key held by the seller;
/// the app verifies it with the embedded public key — no network, so it keeps
/// the "collects nothing, sends nothing" privacy promise.
public struct License: Codable, Sendable, Equatable {
    /// Who the license was issued to (email or name) — informational.
    public let licensee: String
    public let tier: Tier
    public let issuedAt: Date
    /// nil = perpetual; otherwise the license is invalid once past this date.
    public let expiresAt: Date?

    public init(licensee: String, tier: Tier = .pro, issuedAt: Date, expiresAt: Date? = nil) {
        self.licensee = licensee
        self.tier = tier
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }
}

/// The on-disk license file: the exact signed payload bytes (base64) plus the
/// Ed25519 signature (base64). Storing the raw payload avoids re-encoding
/// mismatches between signing and verification.
public struct LicenseEnvelope: Codable, Sendable, Equatable {
    public let payload: String // base64 of the License JSON that was signed
    public let signature: String // base64 Ed25519 signature over those bytes

    public init(payload: String, signature: String) {
        self.payload = payload
        self.signature = signature
    }
}

/// The Ed25519 public key used to verify licenses, base64 (raw 32 bytes).
/// EMPTY by default — set it to your real public key (printed by
/// scripts/license-keygen.sh) before shipping paid builds. While empty, no
/// license verifies and every build stays on the free tier.
public enum LicensePublicKey {
    public static let base64 = ""
}

/// Verifies signed licenses with an Ed25519 public key.
public struct LicenseVerifier: Sendable {
    private let publicKey: Curve25519.Signing.PublicKey

    public enum Error: Swift.Error { case invalidPublicKey }

    public init(publicKeyBase64: String) throws {
        guard let data = Data(base64Encoded: publicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: data)
        else { throw Error.invalidPublicKey }
        publicKey = key
    }

    public func isValid(payload: Data, signature: Data) -> Bool {
        publicKey.isValidSignature(signature, for: payload)
    }
}

/// A gate backed by a verified license.
public struct SignedLicenseGate: LicenseGate {
    public let license: License
    public init(license: License) {
        self.license = license
    }

    public var tier: Tier {
        license.tier
    }
}

/// Imposes no limits. Used before monetization is configured (no public key
/// embedded) so that, until a Pro offering with a working upgrade path exists,
/// nobody is stranded on the free-tier cap.
public struct UnlimitedLicenseGate: LicenseGate {
    public init() {}
    public var tier: Tier {
        .pro
    }
}

/// Resolves the active gate from the license file:
/// - No public key configured yet (monetization not live) → `UnlimitedLicenseGate`
///   (no limits, so users aren't capped without a way to upgrade).
/// - Configured + a correctly-signed, unexpired license → `SignedLicenseGate`.
/// - Configured, otherwise → `FreeLicenseGate`.
/// Never throws: any problem downgrades to the free tier.
public enum LicenseLoader {
    public static func gate(
        licenseFileURL: URL,
        publicKeyBase64: String = LicensePublicKey.base64,
        now: Date = Date()
    ) -> LicenseGate {
        // Until a real public key is embedded, the paid path can't work — so
        // don't enforce any paid limits.
        guard !publicKeyBase64.isEmpty else { return UnlimitedLicenseGate() }

        guard let verifier = try? LicenseVerifier(publicKeyBase64: publicKeyBase64),
              let data = try? Data(contentsOf: licenseFileURL),
              let envelope = try? JSONDecoder().decode(LicenseEnvelope.self, from: data),
              let payload = Data(base64Encoded: envelope.payload),
              let signature = Data(base64Encoded: envelope.signature),
              verifier.isValid(payload: payload, signature: signature),
              let license = try? JSONDecoder().decode(License.self, from: payload),
              license.expiresAt.map({ $0 >= now }) ?? true
        else {
            return FreeLicenseGate()
        }
        return SignedLicenseGate(license: license)
    }
}
