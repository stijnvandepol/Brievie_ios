import BrievieCore
@testable import FeaturePairing
import Foundation
import Testing

/// The sheet behind a `brievie://server` link: offer, refusals and pairing by proof (Review Focus 1, 4, 5, 6).
@MainActor
@Suite struct ServerLinkModelTests {
    private let fixture = ServerLinkFixture()

    // MARK: - Receiving

    @Test func receivingALinkSendsNothing() throws {
        let model = fixture.makeModel()

        model.receive(try fixture.url(ServerLinkFixture.publicLink), appState: fixture.unpaired)

        #expect(model.presentation == .offer(address: "brievie.example.nl", failure: nil, isPairing: false))
        #expect(fixture.server.healthCalls == 0)
        #expect(fixture.server.challengeCalls == 0)
        #expect(fixture.server.proofCalls == 0)
        fixture.expectNothingStored()
    }

    @Test func offerShowsTheAddressNotTheLink() throws {
        let model = fixture.makeModel()

        model.receive(try fixture.url(ServerLinkFixture.pinnedLink), appState: fixture.unpaired)

        #expect(model.presentation == .offer(address: "brievie.local", failure: nil, isPairing: false))
        let shown = String(describing: model.presentation)
        for hidden in [ServerLinkFixture.pin, ServerLinkFixture.pairingID, "https"] {
            #expect(!shown.contains(hidden))
        }
    }

    @Test func malformedAndNewerLinksAreOneSentenceEach() throws {
        let model = fixture.makeModel()

        model.receive(try fixture.url("brievie://server#v=1&url=http%3A%2F%2Fx.nl&pairing=\(ServerLinkFixture.pairingID)"), appState: fixture.unpaired)
        #expect(model.presentation == .notice(PairingStrings.linkInvalid))

        model.receive(try fixture.url("brievie://server#v=2&url=https%3A%2F%2Fx.nl"), appState: fixture.unpaired)
        #expect(model.presentation == .notice(PairingStrings.linkUnsupportedVersion))
        #expect(fixture.server.healthCalls == 0)
    }

    @Test func anAlreadyPairedAppRefusesAndChangesNothing() throws {
        let model = fixture.makeModel()

        model.receive(try fixture.url(ServerLinkFixture.publicLink), appState: fixture.ready())

        #expect(model.presentation == .notice(PairingStrings.linkAlreadyPaired))
        #expect(fixture.server.healthCalls == 0)
        fixture.expectNothingStored()
        #expect(fixture.paired.connections.isEmpty)
        #expect(!model.canSubmit)
    }

    @Test func aLockedAppDropsTheLink() throws {
        let model = fixture.makeModel()

        model.receive(try fixture.url(ServerLinkFixture.publicLink), appState: .locked)
        #expect(model.presentation == nil)

        model.appStateChanged(fixture.ready())
        #expect(model.presentation == nil)
        #expect(fixture.server.healthCalls == 0)
    }

    @Test func lockingClosesTheSheet() throws {
        let model = try fixture.offered()

        model.appStateChanged(.locked)

        #expect(model.presentation == nil)
        #expect(model.code.isEmpty)
    }

    @Test func pairingWithQRMeanwhileClosesTheOffer() throws {
        let model = try fixture.offered()

        model.appStateChanged(fixture.ready())

        #expect(model.presentation == nil)
    }

    @Test func aNewLinkReplacesTheOfferAndClearsTheCode() throws {
        let model = try fixture.offered()

        model.receive(try fixture.url(ServerLinkFixture.pinnedLink), appState: fixture.unpaired)

        #expect(model.presentation == .offer(address: "brievie.local", failure: nil, isPairing: false))
        #expect(model.code.isEmpty)
    }

    @Test func dismissClosesAndForgets() throws {
        let model = try fixture.offered()

        model.dismiss()

        #expect(model.presentation == nil)
        #expect(model.code.isEmpty)
        model.submit()
        #expect(fixture.server.healthCalls == 0)
    }

    // MARK: - The typed code

    @Test(arguments: ["", "ABCD-23", "ABCD-23456", "ABCD-23!5"])
    func pairingNeedsAValidTypedCode(code: String) async throws {
        let model = try fixture.offered(code: code)

        #expect(!model.canSubmit)
        await fixture.submitAndWait(model)

        #expect(fixture.server.healthCalls == 0)
    }

    @Test func noOfferNoSubmit() {
        let model = fixture.makeModel()
        model.code = "ABCD-2345"

        #expect(!model.canSubmit)
    }

    @Test func aTypedCodePairsByProof() async throws {
        let model = try fixture.offered(code: "abcd 2345")
        #expect(model.canSubmit)

        await fixture.submitAndWait(model)

        #expect(fixture.server.proofCalls == 1)
        #expect(fixture.server.pairCalls == 0)
        #expect(fixture.server.codes.isEmpty)
        #expect(!fixture.server.proofs.contains { "\($0)".uppercased().contains("ABCD") })
        #expect(fixture.server.deviceNames == ["Stijns iPhone"])
        #expect(fixture.paired.connections.count == 1)
        #expect(model.presentation == nil)
        #expect(model.code.isEmpty)
        #expect(fixture.secrets.read(.deviceToken) != nil)
    }

    @Test func anEmptyDeviceNameFallsBackToTheModelName() async throws {
        let model = fixture.makeModel(deviceName: "  ")
        model.receive(try fixture.url(ServerLinkFixture.publicLink), appState: fixture.unpaired)
        model.code = "ABCD-2345"

        await fixture.submitAndWait(model)

        #expect(fixture.server.deviceNames == ["iPhone"])
    }

    @Test func theLinkPairingIsTheSameServerAsTheQrPairing() async throws {
        let model = try fixture.offered()
        await fixture.submitAndWait(model)
        let byLink = try #require(fixture.paired.connections.first)

        let qrSecrets = InMemorySecretStore()
        let byQR = try await PairingService(server: fixture.server, store: ConnectionStore(secrets: qrSecrets))
            .pair(try PairingPayload.parse(ServerLinkFixture.qrPayload), deviceName: "iPhone")

        #expect(byLink.serverID == byQR.serverID)
    }

    @Test func aDoubleTapPairsOnce() async throws {
        let gate = Gate()
        fixture.server.proof = {
            await gate.pass()
            return StubServer.device
        }
        let model = try fixture.offered()

        model.submit()
        let first = model.pairingTask
        model.submit()
        #expect(model.pairingTask == first)
        await gate.waitForArrival()
        gate.open()
        await first?.value

        #expect(fixture.server.proofCalls == 1)
        #expect(fixture.paired.connections.count == 1)
    }

    @Test func linksAreIgnoredWhilePairing() async throws {
        let gate = Gate()
        fixture.server.proof = {
            await gate.pass()
            return StubServer.device
        }
        let model = try fixture.offered()
        model.submit()
        await gate.waitForArrival()

        #expect(model.presentation == .offer(address: "brievie.example.nl", failure: nil, isPairing: true))
        model.receive(try fixture.url(ServerLinkFixture.pinnedLink), appState: fixture.unpaired)
        model.appStateChanged(.locked)
        model.dismiss()
        #expect(model.presentation == .offer(address: "brievie.example.nl", failure: nil, isPairing: true))
        #expect(!model.canSubmit)

        gate.open()
        await model.pairingTask?.value
        #expect(fixture.paired.connections.count == 1)
    }
}
