@testable import BrievieCore
import Testing

@Suite struct AppStringsTests {
    @Test func catalogAndCodeAgree() throws {
        let expected = [
            ("lock.reason", AppStrings.lockReason),
            ("session.revoked", AppStrings.sessionRevoked),
            ("error.generic", AppStrings.genericError),
            ("unpair.serverStillKnowsDevice", AppStrings.serverStillKnowsDevice)
        ]
        for (key, resolved) in expected {
            #expect(try CatalogParity.dutchValue(forKey: key, target: "BrievieCore") == resolved, "\(key)")
        }
    }
}
