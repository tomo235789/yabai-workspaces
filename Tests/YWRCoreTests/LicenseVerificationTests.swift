import CryptoKit
import XCTest
@testable import YWRCore

final class LicenseVerificationTests: XCTestCase {
    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ywr-license-\(UUID().uuidString).json")
    }

    /// Signs a license with a fresh key and writes the envelope; returns the file
    /// URL and the matching public key (base64).
    private func writeLicense(_ license: License, to url: URL) throws -> String {
        let priv = Curve25519.Signing.PrivateKey()
        let payload = try JSONEncoder().encode(license)
        let signature = try priv.signature(for: payload)
        let envelope = LicenseEnvelope(payload: payload.base64EncodedString(),
                                       signature: signature.base64EncodedString())
        try JSONEncoder().encode(envelope).write(to: url)
        return priv.publicKey.rawRepresentation.base64EncodedString()
    }

    func testValidLicenseUnlocksProTier() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let license = License(licensee: "a@b.com", issuedAt: Date(timeIntervalSince1970: 0))
        let pub = try writeLicense(license, to: url)

        let gate = LicenseLoader.gate(licenseFileURL: url, publicKeyBase64: pub,
                                      now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(gate.tier, .pro)
        XCTAssertTrue(gate.isEntitled(to: .unlimitedSnapshots))
    }

    func testTamperedPayloadFallsBackToFree() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let pub = try writeLicense(License(licensee: "a", issuedAt: Date(timeIntervalSince1970: 0)), to: url)
        // Corrupt the stored payload so the signature no longer matches.
        var env = try JSONDecoder().decode(LicenseEnvelope.self, from: Data(contentsOf: url))
        env = LicenseEnvelope(payload: Data("forged".utf8).base64EncodedString(), signature: env.signature)
        try JSONEncoder().encode(env).write(to: url)

        let gate = LicenseLoader.gate(licenseFileURL: url, publicKeyBase64: pub)
        XCTAssertEqual(gate.tier, .free)
    }

    func testWrongPublicKeyFallsBackToFree() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        _ = try writeLicense(License(licensee: "a", issuedAt: Date(timeIntervalSince1970: 0)), to: url)
        let otherKey = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()

        let gate = LicenseLoader.gate(licenseFileURL: url, publicKeyBase64: otherKey)
        XCTAssertEqual(gate.tier, .free)
    }

    func testExpiredLicenseFallsBackToFree() throws {
        let url = tempURL(); defer { try? FileManager.default.removeItem(at: url) }
        let license = License(licensee: "a", issuedAt: Date(timeIntervalSince1970: 0),
                              expiresAt: Date(timeIntervalSince1970: 50))
        let pub = try writeLicense(license, to: url)

        let gate = LicenseLoader.gate(licenseFileURL: url, publicKeyBase64: pub,
                                      now: Date(timeIntervalSince1970: 100)) // past expiry
        XCTAssertEqual(gate.tier, .free)
    }

    func testUnconfiguredKeyImposesNoLimits() {
        // Empty public key = monetization not live yet → no cap, no stranded users.
        let gate = LicenseLoader.gate(licenseFileURL: tempURL(), publicKeyBase64: "")
        XCTAssertTrue(gate.canSaveNewSnapshot(existingCount: 999))
        XCTAssertTrue(gate.isEntitled(to: .unlimitedSnapshots))
    }

    func testConfiguredButMissingFileIsFree() {
        // A real key is configured but no license present → free tier (capped).
        let key = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        let gate = LicenseLoader.gate(licenseFileURL: tempURL(), publicKeyBase64: key)
        XCTAssertEqual(gate.tier, .free)
        XCTAssertFalse(gate.canSaveNewSnapshot(existingCount: LicenseLimits.freeSnapshotLimit))
    }

    func testFreeSnapshotCapAndProLift() {
        let free = FreeLicenseGate()
        XCTAssertTrue(free.canSaveNewSnapshot(existingCount: LicenseLimits.freeSnapshotLimit - 1))
        XCTAssertFalse(free.canSaveNewSnapshot(existingCount: LicenseLimits.freeSnapshotLimit))

        struct ProGate: LicenseGate { var tier: Tier {
            .pro
        } }
        XCTAssertTrue(ProGate().canSaveNewSnapshot(existingCount: 999))
    }
}
