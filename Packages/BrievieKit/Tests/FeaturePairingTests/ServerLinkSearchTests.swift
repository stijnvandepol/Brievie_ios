import BrievieCore
@testable import FeaturePairing
import Foundation
import Testing

/// The address on screen while the code is typed is the address the proof goes to, and pairing never goes
/// anywhere else (security review, fix round 1).
@MainActor
@Suite struct ServerLinkSearchTests {
    private let fixture = ServerLinkFixture()

    // MARK: - Nothing is contacted before the user's tap

    @Test func openingALinkContactsNothingUntilTheTap() async throws {
        let model = fixture.makeModel()

        model.receive(try fixture.url(ServerLinkFixture.publicLink), appState: fixture.unpaired)

        #expect(model.presentation == .question)
        #expect(model.searchTask == nil)
        #expect(!model.canSubmit)
        #expect(!model.asksForCode)
        await Task.yield()
        #expect(fixture.server.healthCalls == 0)
        #expect(fixture.server.contactedHosts.isEmpty)

        model.findServer()
        await model.searchTask?.value

        #expect(fixture.server.healthCalls == 1)
    }

    @Test func cancellingTheQuestionContactsNothing() async throws {
        let model = fixture.makeModel()
        model.receive(try fixture.url(ServerLinkFixture.publicLink), appState: fixture.unpaired)

        model.dismiss()
        model.findServer()
        await Task.yield()

        #expect(model.presentation == nil)
        #expect(model.searchTask == nil)
        #expect(fixture.server.healthCalls == 0)
        fixture.expectNothingStored()
    }

    @Test func aSecondLinkBeforeTheTapReplacesTheFirstWithoutContact() async throws {
        let model = fixture.makeModel()
        model.receive(try fixture.url(ServerLinkFixture.publicLink), appState: fixture.unpaired)

        model.receive(try fixture.url(ServerLinkFixture.otherLink), appState: fixture.unpaired)
        #expect(model.presentation == .question)
        #expect(fixture.server.healthCalls == 0)

        model.findServer()
        await model.searchTask?.value
        #expect(fixture.server.contactedHosts == ["other.example.nl"])
        #expect(model.presentation == .offer(address: "other.example.nl", failure: nil, isPairing: false))
    }

    @Test func theTapIsIgnoredWithoutAQuestion() async throws {
        let model = fixture.makeModel()

        model.findServer()
        model.receive(try fixture.url(ServerLinkFixture.publicLink), appState: fixture.ready())
        model.findServer()

        #expect(model.presentation == .notice(PairingStrings.linkAlreadyPaired, kind: .warning))
        #expect(fixture.server.healthCalls == 0)
    }

    // MARK: - The address is fixed before the code

    @Test func anUnreachableFirstAddressShowsTheSecondBeforeTheCode() async throws {
        fixture.server.unreachableHosts = ["first.example.nl"]
        let model = fixture.makeModel()

        await fixture.receive(try fixture.link(["first.example.nl", "second.example.nl"]), on: model)

        #expect(model.presentation == .offer(address: "second.example.nl", failure: nil, isPairing: false))
        model.code = "ABCD-2345"
        await fixture.submitAndWait(model)
        #expect(fixture.server.challengeURLs.compactMap { $0.host() } == ["second.example.nl"])
        #expect(fixture.server.proofURLs.compactMap { $0.host() } == ["second.example.nl"])
        #expect(fixture.paired.connections.count == 1)
    }

    @Test func anUnbindableFirstAddressIsNeverContacted() async throws {
        let model = fixture.makeModel()

        await fixture.receive(try fixture.link(["brievie.local%3A8443", "second.example.nl%3A8443"]), on: model)

        #expect(model.presentation == .offer(address: "second.example.nl:8443", failure: nil, isPairing: false))
        #expect(fixture.server.contactedHosts == ["second.example.nl"])
    }

    @Test(arguments: [ServerError.unreachable, .untrusted])
    func aFailedChallengeAfterTheCodeNeverTriesAnotherAddress(error: ServerError) async throws {
        fixture.server.challenge = { throw error }
        let model = fixture.makeModel()
        await fixture.receive(try fixture.link(["first.example.nl", "second.example.nl"]), on: model)
        model.code = "ABCD-2345"

        await fixture.submitAndWait(model)

        #expect(model.presentation == .offer(
            address: "first.example.nl", failure: PairingStrings.unreachable, isPairing: false
        ))
        #expect(fixture.server.contactedHosts == ["first.example.nl"])
        #expect(fixture.server.proofCalls == 0)
    }

    @Test func aLostConnectionAfterTheProofNeverTriesAnotherAddress() async throws {
        fixture.server.proof = { throw ServerError.unreachable }
        let model = fixture.makeModel()
        await fixture.receive(try fixture.link(["first.example.nl", "second.example.nl"]), on: model)
        model.code = "ABCD-2345"

        await fixture.submitAndWait(model)
        model.code = "ABCD-2345"
        await fixture.submitAndWait(model)

        #expect(fixture.server.contactedHosts == ["first.example.nl"])
        #expect(fixture.server.proofURLs.compactMap { $0.host() } == ["first.example.nl", "first.example.nl"])
    }

    @Test func whenNoAddressAnswersThereIsNoCodeField() async throws {
        fixture.server.unreachableHosts = ["first.example.nl", "second.example.nl"]
        let model = fixture.makeModel()

        await fixture.receive(try fixture.link(["first.example.nl", "second.example.nl"]), on: model)

        #expect(model.presentation == .notice(PairingStrings.unreachable, kind: .error))
        model.code = "ABCD-2345"
        #expect(!model.canSubmit)
        #expect(!model.asksForCode)
    }

    @Test func anIncompatibleServerIsANoticeBeforeTheCode() async throws {
        fixture.server.health = { "2.0.0" }
        let model = fixture.makeModel()

        await fixture.receive(try fixture.url(ServerLinkFixture.publicLink), on: model)

        #expect(model.presentation == .notice(PairingStrings.incompatible, kind: .error))
    }

    @Test func lockingWhileSearchingClosesAndDropsTheResult() async throws {
        let gate = Gate()
        fixture.server.healthGate = gate
        let model = fixture.makeModel()
        model.receive(try fixture.url(ServerLinkFixture.publicLink), appState: fixture.unpaired)
        model.findServer()
        await gate.waitForArrival()

        model.appStateChanged(.locked)
        gate.open()
        await model.searchTask?.value

        #expect(model.presentation == nil)
    }

    @Test func aNewLinkWhileSearchingReplacesTheSearch() async throws {
        let gate = Gate()
        fixture.server.healthGate = gate
        let model = fixture.makeModel()
        model.receive(try fixture.url(ServerLinkFixture.publicLink), appState: fixture.unpaired)
        model.findServer()
        let first = model.searchTask
        await gate.waitForArrival()
        fixture.server.healthGate = nil

        await fixture.receive(try fixture.url(ServerLinkFixture.otherLink), on: model)
        gate.open()
        await first?.value

        #expect(model.presentation == .offer(address: "other.example.nl", failure: nil, isPairing: false))
    }

    @Test func theCodeEntryAsksForThePrivacyCover() async throws {
        let model = try await fixture.offered()
        #expect(model.asksForCode)

        model.dismiss()
        #expect(!model.asksForCode)
    }
}
