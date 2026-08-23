import XCTest
@testable import YWRCore

final class LicensingTests: XCTestCase {
    func testFreeGateIsFreeTierWithNoEntitlements() {
        let gate = FreeLicenseGate()
        XCTAssertEqual(gate.tier, .free)
        for feature in ProFeature.allCases {
            XCTAssertFalse(gate.isEntitled(to: feature), "free tier must not entitle \(feature)")
        }
    }

    func testResolveFallsBackToFreeWhenNoProvider() {
        let gate = resolveLicenseGate(nil)
        XCTAssertEqual(gate.tier, .free)
    }

    func testResolveUsesProviderGate() {
        struct ProGate: LicenseGate { var tier: Tier {
            .pro
        } }
        struct StubPro: ProProvider { var licenseGate: LicenseGate {
            ProGate()
        } }

        let gate = resolveLicenseGate(StubPro())
        XCTAssertEqual(gate.tier, .pro)
        // Default all-or-nothing entitlement unlocks every Pro feature.
        for feature in ProFeature.allCases {
            XCTAssertTrue(gate.isEntitled(to: feature))
        }
    }

    func testPerFeatureGateCanOverrideEntitlement() {
        struct PartialGate: LicenseGate {
            var tier: Tier {
                .pro
            }

            func isEntitled(to feature: ProFeature) -> Bool {
                feature == .autoRestore
            }
        }
        let gate = PartialGate()
        XCTAssertTrue(gate.isEntitled(to: .autoRestore))
        XCTAssertFalse(gate.isEntitled(to: .cloudSync))
    }
}
