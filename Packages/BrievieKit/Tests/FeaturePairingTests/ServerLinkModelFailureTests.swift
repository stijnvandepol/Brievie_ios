import BrievieCore
@testable import FeaturePairing
import Foundation
import Testing

/// What the link sheet shows when pairing fails, and its texts.
@MainActor
@Suite struct ServerLinkModelFailureTests {
    private let fixture = ServerLinkFixture()

    // MARK: - Failures

    /// A wrong proof, an unknown pairing, an expired or replayed challenge: `LiveBrievieServer` maps them all to
    /// `.invalidCode` (`LiveBrievieServerProofTests`), so the user reads one sentence for each.
    @Test func aRefusedProofClearsTheFieldAndKeepsTheOffer() async throws {
        fixture.server.proof = { throw ServerError.invalidCode }
        let model = try fixture.offered()

        await fixture.submitAndWait(model)

        #expect(model.presentation == .offer(
            address: "brievie.example.nl", failure: PairingStrings.linkInvalidCode, isPairing: false
        ))
        #expect(model.code.isEmpty)
        fixture.expectNothingStored()
    }

    @Test(arguments: [ServerError.unreachable, .untrusted])
    func aConnectionLostAfterTheProofClearsTheField(error: ServerError) async throws {
        fixture.server.proof = { throw error }
        let model = try fixture.offered()

        await fixture.submitAndWait(model)

        #expect(model.presentation == .offer(
            address: "brievie.example.nl", failure: PairingStrings.connectionLost, isPairing: false
        ))
        #expect(model.code.isEmpty)
    }

    @Test func anUnreachableServerKeepsTheCode() async throws {
        fixture.server.health = { throw ServerError.unreachable }
        let model = try fixture.offered(code: "ABCD-2345")
        await fixture.submitAndWait(model)
        #expect(model.presentation == .offer(
            address: "brievie.example.nl", failure: PairingStrings.unreachable, isPairing: false
        ))
        #expect(model.code == "ABCD-2345")
        #expect(model.canSubmit)

        fixture.server.health = { "1.0.0" }
        fixture.server.challenge = { throw ServerError.tooManyAttempts }
        await fixture.submitAndWait(model)
        #expect(model.presentation == .offer(
            address: "brievie.example.nl", failure: PairingStrings.tooManyAttempts, isPairing: false
        ))
        #expect(model.code == "ABCD-2345")

        fixture.server.challenge = { throw ServerError.other("http_404") }
        await fixture.submitAndWait(model)
        #expect(model.presentation == .offer(
            address: "brievie.example.nl", failure: PairingStrings.incompatible, isPairing: false
        ))
        #expect(model.code == "ABCD-2345")
        #expect(fixture.server.proofCalls == 0)
    }

    @Test func diagnosticTextNeverReachesTheUser() async throws {
        fixture.server.proof = { throw ServerError.other("http_503_secret_detail") }
        let model = try fixture.offered()

        await fixture.submitAndWait(model)

        #expect(model.presentation == .offer(
            address: "brievie.example.nl", failure: PairingStrings.generic, isPairing: false
        ))
    }

    @Test func aCancelledPairingReturnsToTheIdleOffer() async throws {
        fixture.server.health = { throw CancellationError() }
        let model = try fixture.offered()

        await fixture.submitAndWait(model)

        #expect(model.presentation == .offer(address: "brievie.example.nl", failure: nil, isPairing: false))
        #expect(fixture.paired.connections.isEmpty)
    }

    @Test func aPairingThatSucceededDespiteCancellationIsStillReported() async throws {
        fixture.server.proof = {
            withUnsafeCurrentTask { $0?.cancel() }
            return StubServer.device
        }
        let model = try fixture.offered()

        await fixture.submitAndWait(model)

        #expect(fixture.paired.connections.count == 1)
        #expect(fixture.secrets.read(.deviceToken) != nil)
        #expect(model.presentation == nil)
    }

    // MARK: - Copy

    @Test func catalogAndCodeAgree() throws {
        for (key, resolved) in PairingStrings.all {
            #expect(try CatalogParity.dutchValue(forKey: key, target: "FeaturePairing") == resolved, "\(key)")
        }
    }

    @Test func linkTextsUseTheAgreedWording() {
        #expect(PairingStrings.linkInvalid
            == "Deze link werkt niet. Maak op de webpagina een nieuwe koppelcode en open de link opnieuw.")
        #expect(PairingStrings.linkUnsupportedVersion
            == "Deze link komt van een nieuwere versie van Brievie. Werk de app bij en probeer het opnieuw.")
        #expect(PairingStrings.linkAlreadyPaired == "Deze telefoon is al gekoppeld met een Brievie-server. "
            + "Wil je een andere server gebruiken? Tik dan in je werkruimtes op Ontkoppelen en open de link opnieuw.")
    }
}
