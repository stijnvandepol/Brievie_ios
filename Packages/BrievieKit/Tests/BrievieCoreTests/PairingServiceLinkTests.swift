@testable import BrievieCore
import Foundation
import Testing

/// Pairing from a `brievie://server` link: the typed code never leaves the phone (D 6.2 as changed by D 20).
@Suite struct PairingServiceLinkTests {
    private let harness: PairingHarness
    private var server: FakeBrievieServer { harness.server }
    private var home: URL { harness.home }
    private var away: URL { harness.away }
    private let code: PairingCode
    private static let pairingID = "0b7e2f4c-5d1a-4e8b-9c3f-6a2d8e1f4b70"

    init() throws {
        harness = try PairingHarness()
        code = try #require(PairingCode(typed: "abcd-2345"))
    }

    private func pin() throws -> String {
        try Fixtures.text("ca.sha256").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func link(_ urls: [URL], pin: String?) throws -> ServerLink {
        var fields = ["v=1"]
        fields += urls.map { url in
            "url=" + (url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
        }
        if let pin { fields.append("ca_sha256=\(pin)") }
        fields.append("pairing=\(Self.pairingID)")
        return try ServerLink.parse(try #require(URL(string: "brievie://server#" + fields.joined(separator: "&"))))
    }

    private func pinnedLink() throws -> ServerLink {
        try link([home, away], pin: try pin())
    }

    private func expectedProof(binding: String) throws -> String {
        let pairingID = try #require(UUID(uuidString: Self.pairingID))
        let key = try #require(PairingProof.key(code: code, pairingID: pairingID))
        return try #require(PairingProof.proof(key: key, nonce: FakeBrievieServer.nonce, trustBinding: binding))
    }

    private func pairingError(
        _ link: ServerLink, sourceLocation: SourceLocation = #_sourceLocation
    ) async -> PairingError? {
        do {
            _ = try await harness.service.pair(link: link, code: code, deviceName: "iPhone")
            Issue.record("Pairing succeeded", sourceLocation: sourceLocation)
            return nil
        } catch {
            return error
        }
    }

    // MARK: - The code stays on the phone

    @Test func theLinkPathNeverSendsTheCode() async throws {
        _ = try await harness.service.pair(link: try pinnedLink(), code: code, deviceName: "iPhone")

        #expect(server.calls.filter(\.isPair).isEmpty)
        for call in server.calls {
            let text = String(describing: call)
            for secret in ["ABCD2345", "ABCD-2345", "ABCD", "2345"] { #expect(!text.contains(secret), "\(secret)") }
        }
        #expect(server.calls.contains { $0.isProof })
    }

    @Test func aPinnedLinkBindsTheProofToThePinnedCertificate() async throws {
        _ = try await harness.service.pair(link: try pinnedLink(), code: code, deviceName: "iPhone")

        let expected = try expectedProof(binding: try pin())
        let pairingID = try #require(UUID(uuidString: Self.pairingID))
        #expect(server.calls == [
            .caCertificate(home), .health(home), .challenge(home),
            .proof(
                home, CodeProof(pairingID: pairingID, nonce: FakeBrievieServer.nonce, proof: expected), name: "iPhone"
            )
        ])
    }

    @Test func aRelayGetsAProofForItsOwnBinding() async throws {
        let relay = try #require(URL(string: "https://attacker.example.com"))

        _ = try await harness.service.pair(link: try link([relay], pin: nil), code: code, deviceName: "iPhone")

        let sent = server.calls.compactMap(\.sentProof)
        #expect(sent == [try expectedProof(binding: "attacker.example.com")])
        #expect(sent.first != (try expectedProof(binding: "brievie.example.nl")))
    }

    @Test func withoutAPinAnAddressNoAuthorityCertifiesIsNeverContacted() async throws {
        let unpinned = try link([home, away], pin: nil)
        let connection = try await harness.service.pair(link: unpinned, code: code, deviceName: "iPhone")

        #expect(server.calls.first == .health(away))
        #expect(!server.calls.contains { String(describing: $0).contains("brievie.local") })
        #expect(connection.urls == [home, away])
        let proofs = server.calls.compactMap(\.sentProof)
        #expect(proofs == [try expectedProof(binding: "brievie.example.nl")])
    }

    @Test func aLinkWithOnlyUncertifiableAddressesAndNoPinIsRefusedWithoutContact() async throws {
        let lan = try #require(URL(string: "https://192.168.1.4"))

        #expect(await pairingError(try link([home, lan], pin: nil)) == .serverNotVerified)
        #expect(server.calls.isEmpty)
        try harness.expectNothingStored()
    }

    // MARK: - The address is fixed before the code exists

    @Test func locatingFindsTheFirstVerifiedAddressWithoutAnythingFromTheCode() async throws {
        let home = home
        server.health = { url in
            if url == home { throw ServerError.unreachable }
            return "1.0.0"
        }

        let located = try await harness.service.locate(try pinnedLink())

        #expect(located.url == away)
        #expect(located.displayAddress == "brievie.example.nl")
        #expect(!server.calls.contains { $0.isChallenge || $0.isProof || $0.isPair })
    }

    @Test func pairingAtALocatedServerNeverContactsAnotherAddress() async throws {
        let link = try pinnedLink()
        let located = try await harness.service.locate(link)
        server.challenge = { _ in throw ServerError.unreachable }
        let before = server.calls.count

        await #expect(throws: PairingError.noServerReachable) {
            try await harness.service.pair(link: link, at: located, code: code, deviceName: "iPhone")
        }

        #expect(server.calls.dropFirst(before).map { $0 } == [.challenge(home)])
    }

    // MARK: - Verification first, as on the QR path

    @Test func theLinkPairingVerifiesThePinFirst() async throws {
        let other = try Fixtures.text("other-ca.pem")
        server.caPEM = { _ in other }

        #expect(await pairingError(try pinnedLink()) == .serverNotVerified)
        #expect(!server.calls.contains { $0.isChallenge || $0.isProof })
        try harness.expectNothingStored()
    }

    @Test func aTwoXServerIsIncompatibleBeforeAnyChallenge() async throws {
        server.health = { _ in "2.0.0" }

        #expect(await pairingError(try pinnedLink()) == .incompatibleServer)
        #expect(!server.calls.contains { $0.isChallenge || $0.isProof })
    }

    // MARK: - Refusals

    @Test func aServerWithoutTheProofPathIsIncompatible() async throws {
        server.challenge = { _ in throw ServerError.other("http_404") }

        #expect(await pairingError(try pinnedLink()) == .incompatibleServer)
        #expect(!server.calls.contains { $0.isProof || $0.isPair })
        try harness.expectNothingStored()
    }

    @Test(arguments: [ServerError.unreachable, .untrusted])
    func aLostConnectionAtTheChallengeSpentNothing(error: ServerError) async throws {
        server.challenge = { _ in throw error }

        #expect(await pairingError(try pinnedLink()) == .noServerReachable)
        #expect(!server.calls.contains { $0.isProof })
    }

    /// A server (or relay) that hands out a shortened or lengthened nonce gets no proof at all.
    @Test(arguments: [String(FakeBrievieServer.nonce.dropLast()), FakeBrievieServer.nonce + "c"])
    func aNonceOfTheWrongLengthGetsNoProof(nonce: String) async throws {
        server.challenge = { _ in nonce }

        #expect(await pairingError(try pinnedLink()) == .incompatibleServer)
        #expect(!server.calls.contains { $0.isProof })
        try harness.expectNothingStored()
    }

    @Test func tooManyChallengesIsTooManyAttempts() async throws {
        server.challenge = { _ in throw ServerError.tooManyAttempts }

        #expect(await pairingError(try pinnedLink()) == .tooManyAttempts)
    }

    /// A wrong proof, an unknown pairing (both `pairing_code_invalid`) and an expired or replayed challenge
    /// (`pairing_challenge_invalid`) end in the same refusal.
    @Test(arguments: [
        ServerError(status: 400, code: "pairing_code_invalid"),
        ServerError(status: 400, code: "pairing_challenge_invalid")
    ])
    func aRefusedProofIsAnInvalidCode(error: ServerError) async throws {
        server.proof = { _ in throw error }

        #expect(await pairingError(try pinnedLink()) == .invalidCode)
        try harness.expectNothingStored()
    }

    @Test(arguments: [ServerError.unreachable, .untrusted])
    func aLostConnectionAfterTheProofMaySpendTheCode(error: ServerError) async throws {
        server.proof = { _ in throw error }

        #expect(await pairingError(try pinnedLink()) == .connectionLostWhilePairing)
        // Never a second URL once the proof went out.
        #expect(server.calls.filter(\.isProof).count == 1)
        try harness.expectNothingStored()
    }

    @Test func tooManyProofsIsTooManyAttempts() async throws {
        server.proof = { _ in throw ServerError.tooManyAttempts }

        #expect(await pairingError(try pinnedLink()) == .tooManyAttempts)
    }

    // MARK: - Storing

    @Test func theLinkPairingStoresTheSameConnectionAsTheQrPath() async throws {
        let byLink = try await harness.service.pair(link: try pinnedLink(), code: code, deviceName: "iPhone")
        let scanned = try PairingHarness()
        let byQR = try await scanned.pair()

        #expect(byLink == byQR)
        let stored = try #require(try harness.store.load())
        #expect(stored.connection == byLink)
        #expect(stored.token == FakeBrievieServer.device.token)
    }

    @Test func anEmptyTokenIsIncompatibleAndStoresNothing() async throws {
        server.proof = { _ in PairedDevice(deviceID: UUID(), token: "", userName: "x") }

        #expect(await pairingError(try pinnedLink()) == .incompatibleServer)
        try harness.expectNothingStored()
    }

    @Test func theQrPathStillSendsTheCode() async throws {
        _ = try await harness.pair()

        #expect(server.calls.contains(.pair(home, code: "ABCD-EFGH", name: "iPhone")))
        #expect(!server.calls.contains { $0.isChallenge || $0.isProof })
    }
}
