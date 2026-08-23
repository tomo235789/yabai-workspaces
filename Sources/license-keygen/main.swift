import CryptoKit
import Foundation
import YWRCore

// Seller-only tool for the offline license scheme.
//
//   swift run license-keygen keypair
//       → prints a new Ed25519 PRIVATE key (keep secret) and PUBLIC key (embed in
//         Sources/YWRCore/Licensing/License.swift → LicensePublicKey.base64).
//
//   YWR_LICENSE_PRIVATE_KEY=<privateBase64> \
//     swift run license-keygen sign <licensee> [expiresISO8601]
//       → prints a signed license.json for the buyer to drop at
//         ~/.config/yabai-workspaces/license.json
//
// The PRIVATE key is read from the environment (never an argument, which would
// leak it via process listings / shell history / CI logs) and must never be
// committed — inject it from a secrets store.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    fail("usage: license-keygen <keypair | sign <licensee> [expiresISO8601]>  (private key via YWR_LICENSE_PRIVATE_KEY)")
}

switch command {
case "keypair":
    let key = Curve25519.Signing.PrivateKey()
    print("PRIVATE (keep secret): \(key.rawRepresentation.base64EncodedString())")
    print("PUBLIC  (LicensePublicKey.base64): \(key.publicKey.rawRepresentation.base64EncodedString())")

case "sign":
    // Private key from the environment, not an argument (avoids leaking it).
    guard let privateBase64 = ProcessInfo.processInfo.environment["YWR_LICENSE_PRIVATE_KEY"],
          let privateData = Data(base64Encoded: privateBase64),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateData)
    else {
        fail("set YWR_LICENSE_PRIVATE_KEY to the base64 Ed25519 private key")
    }
    guard args.count >= 2 else {
        fail("usage: license-keygen sign <licensee> [expiresISO8601]")
    }
    var expiresAt: Date?
    if args.count >= 3 {
        guard let date = ISO8601DateFormatter().date(from: args[2]) else {
            fail("invalid ISO8601 date: \(args[2])")
        }
        expiresAt = date
    }
    let license = License(licensee: args[1], tier: .pro, issuedAt: Date(), expiresAt: expiresAt)
    do {
        let payload = try JSONEncoder().encode(license)
        let signature = try key.signature(for: payload)
        let envelope = LicenseEnvelope(payload: payload.base64EncodedString(),
                                       signature: signature.base64EncodedString())
        let out = try JSONEncoder().encode(envelope)
        FileHandle.standardOutput.write(out)
        print()
    } catch {
        fail("failed to sign license: \(error)")
    }

default:
    fail("unknown command '\(command)'")
}
