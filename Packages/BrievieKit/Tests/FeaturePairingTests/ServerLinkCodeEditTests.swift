import BrievieCore
@testable import FeaturePairing
import Foundation
import Testing

/// After a refused code the message goes once the user types again (simulator, 20-11-2026: it stayed and pushed
/// "Koppel" out of view), and the name the server shows for this phone can be chosen.
@MainActor
@Suite struct ServerLinkCodeEditTests {
    private let fixture = ServerLinkFixture()

    @Test func typingANewCodeClearsTheRefusal() async throws {
        fixture.server.proof = { throw ServerError.invalidCode }
        let model = try await fixture.offered()
        await fixture.submitAndWait(model)
        #expect(model.presentation == .offer(
            address: "brievie.example.nl", failure: PairingStrings.linkInvalidCode, isPairing: false
        ))

        model.code = "A"

        #expect(model.presentation == .offer(address: "brievie.example.nl", failure: nil, isPairing: false))
    }

    @Test func theNameStartsAsThePhonesNameAndIsSent() async throws {
        let model = try await fixture.offered()
        #expect(model.deviceNameField == "Stijns iPhone")

        await fixture.submitAndWait(model)

        #expect(fixture.server.deviceNames == ["Stijns iPhone"])
    }

    @Test func aChosenNameIsSentTrimmed() async throws {
        let model = try await fixture.offered()
        model.deviceNameField = "  iPhone van Jesse "

        await fixture.submitAndWait(model)

        #expect(fixture.server.deviceNames == ["iPhone van Jesse"])
    }

    @Test func anEmptyNameFallsBackToTheDefault() async throws {
        let model = try await fixture.offered()
        model.deviceNameField = "   "

        await fixture.submitAndWait(model)

        #expect(fixture.server.deviceNames == ["iPhone"])
    }

    @Test func aNameLongerThanTheServerTakesIsCut() async throws {
        let model = try await fixture.offered()
        model.deviceNameField = String(repeating: "é", count: 150)

        await fixture.submitAndWait(model)

        #expect(fixture.server.deviceNames.first?.unicodeScalars.count == ServerLinkModel.maxDeviceNameLength)
    }
}
