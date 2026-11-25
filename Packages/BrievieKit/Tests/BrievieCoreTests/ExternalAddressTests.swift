@testable import BrievieCore
import Foundation
import Testing

/// External access (host PR #53, as amended by its security review): pairing stays CA-pinned; public addresses
/// come only from what the server sent over a pinned connection and must be https entries of its `urls`; only
/// those get system trust.
@Suite struct ExternalAddressTests {
    private static let home = URL(string: "https://brievie.local:8443") ?? URL(fileURLWithPath: "/")
    private static let tunnel = URL(string: "https://post.example.nl") ?? URL(fileURLWithPath: "/")
    private static let foreign = URL(string: "https://elsewhere.example.com") ?? URL(fileURLWithPath: "/")

    private func pinned(publicURLs: [URL]? = nil, checkedAt: Date? = nil) throws -> ServerConnection {
        ServerConnection(
            urls: [Self.home, Self.tunnel], caCertificateDER: try Fixtures.der("ca.pem"), deviceID: UUID(),
            userName: "Lid", publicURLs: publicURLs, addressesCheckedAt: checkedAt
        )
    }

    // MARK: - Trust per address

    @Test func publicHostUsesSystemRootsNotTheCA() throws {
        let trust = ServerTrust(caCertificateDER: try Fixtures.der("ca.pem"), publicHosts: ["LOCALHOST"])

        // The leaf is signed by the private CA, which no system root knows: refused on a public host.
        #expect(!trust.evaluate(try Fixtures.serverTrust(leaf: "leaf-a.pem"), host: "localhost"))
    }

    @Test func privateHostStaysAnchoredToTheCA() throws {
        let trust = ServerTrust(caCertificateDER: try Fixtures.der("ca.pem"), publicHosts: ["post.example.nl"])

        #expect(trust.evaluate(try Fixtures.serverTrust(leaf: "leaf-a.pem"), host: "localhost"))
        #expect(!trust.evaluate(try Fixtures.serverTrust(leaf: "other-leaf.pem"), host: "localhost"))
    }

    @Test func aPublicHostNotListedByTheServerStaysAnchored() throws {
        let connection = try pinned(publicURLs: [Self.foreign, Self.tunnel])

        #expect(connection.publicURLs == [Self.tunnel])
        #expect(!connection.isPublic(Self.foreign))
        #expect(connection.isPublic(Self.tunnel))
        #expect(!connection.isPublic(Self.home))
    }

    @Test func withoutACANoAddressIsKeptAsPublic() {
        let connection = ServerConnection(
            urls: [Self.tunnel], caCertificateDER: nil, deviceID: UUID(), userName: "Lid", publicURLs: [Self.tunnel]
        )

        #expect(connection.publicURLs == nil)
    }

    @Test func oldStoredConnectionWithoutPublicURLsStillDecodes() throws {
        let json = #"{"urls":["https://brievie.local"],"deviceID":"\#(UUID().uuidString)","userName":"Lid"}"#

        let connection = try JSONDecoder().decode(ServerConnection.self, from: Data(json.utf8))

        #expect(connection.publicURLs == nil)
        #expect(connection.addressesCheckedAt == nil)
    }

    @Test func storedPublicURLsSurviveTheKeychainRoundTrip() throws {
        let store = ConnectionStore(secrets: InMemorySecretStore())
        let connection = try pinned(publicURLs: [Self.tunnel], checkedAt: Date(timeIntervalSince1970: 1_000))

        try store.save(connection, token: "tok")

        #expect(try store.load()?.connection == connection)
    }

    // MARK: - QR and PairOut

    @Test func theQRsPublicURLsMustBeAmongItsURLs() throws {
        let payload = try PairingPayload.parse(#"""
            {"v":1,"urls":["\#(Self.home)","\#(Self.tunnel)"],"code":"ABCD-EFGH","ca_sha256":null,
             "public_urls":["\#(Self.tunnel)","\#(Self.foreign)","http://post.example.nl"]}
            """#)

        #expect(payload.publicURLs == [Self.tunnel])
    }

    @Test func aHomeQRHasNoPublicURLs() throws {
        let payload = try PairingPayload.parse(#"{"v":1,"urls":["\#(Self.home)"],"code":"ABCD-EFGH","ca_sha256":null}"#)

        #expect(payload.publicURLs.isEmpty)
    }

    @Test func pairingKeepsOnlyTheServersPublicURLsThatAreAmongTheURLs() async throws {
        let harness = try PairingHarness()
        harness.server.pair = { _ in
            PairedDevice(
                deviceID: FakeBrievieServer.device.deviceID, token: "tok", userName: "Lid",
                publicURLs: [harness.away, Self.foreign]
            )
        }

        let connection = try await harness.pair()

        #expect(connection.publicURLs == [harness.away])
        #expect(try harness.store.load()?.connection.publicURLs == [harness.away])
    }

    // MARK: - The public route refuses pairing

    @Test func pairAtHomeIsReadFromTheUndocumented403() async throws {
        let server = LiveBrievieServer(configuration: StubURLProtocol.configuration)
        let url = try StubURLProtocol.serve(.response(
            status: 403, json: #"{"code":"pair_at_home","message":"Koppel de app thuis of via VPN"}"#
        ))

        await #expect(throws: ServerError.other("pair_at_home")) {
            try await server.pair(
                at: url, trust: ServerTrust(caCertificateDER: nil), code: "ABCD-EFGH", deviceName: "x"
            )
        }
        #expect(PairingError(challenge: .other("pair_at_home")) == .pairAtHome)
        #expect(PairingError(pairing: .other("pair_at_home")) == .pairAtHome)
    }

    @Test func a403WithoutABrievieBodyStaysAFixedForm() async throws {
        let server = LiveBrievieServer(configuration: StubURLProtocol.configuration)
        let url = try StubURLProtocol.serve(.data(status: 403, contentType: "text/html", body: Data("<p>no</p>".utf8)))

        await #expect(throws: ServerError.other("http_403")) {
            try await server.pairingChallenge(at: url, trust: ServerTrust(caCertificateDER: nil))
        }
    }

    // MARK: - Learning addresses

    @Test func addressesRefreshAtMostDailyOverAPinnedAddress() throws {
        let now = Date(timeIntervalSince1970: 100_000)

        #expect(AddressRefresh.isDue(try pinned(), at: Self.home, now: now))
        #expect(!AddressRefresh.isDue(try pinned(checkedAt: now.addingTimeInterval(-3_600)), at: Self.home, now: now))
        #expect(AddressRefresh.isDue(try pinned(checkedAt: now.addingTimeInterval(-90_000)), at: Self.home, now: now))
    }

    @Test func refreshNeverAsksOverAPublicOrUnpinnedConnection() throws {
        let now = Date()
        let unpinned = ServerConnection(urls: [Self.home], caCertificateDER: nil, deviceID: UUID(), userName: "Lid")

        #expect(!AddressRefresh.isDue(try pinned(publicURLs: [Self.tunnel]), at: Self.tunnel, now: now))
        #expect(!AddressRefresh.isDue(unpinned, at: Self.home, now: now))
    }

    @Test func refreshAddsTheTunnelWithoutRepairing() throws {
        let now = Date(timeIntervalSince1970: 5_000)
        let old = ServerConnection(
            urls: [Self.home], caCertificateDER: try Fixtures.der("ca.pem"), deviceID: UUID(), userName: "Lid"
        )
        let answer = ServerAddresses(
            urls: [Self.home.absoluteString, Self.tunnel.absoluteString, "http://plain.example.nl"],
            publicURLs: [Self.tunnel.absoluteString, Self.foreign.absoluteString]
        )

        let updated = try #require(AddressRefresh.updated(old, with: answer, now: now))

        #expect(updated.urls == [Self.home, Self.tunnel])
        #expect(updated.publicURLs == [Self.tunnel])
        #expect(updated.deviceID == old.deviceID)
        #expect(updated.serverID == old.serverID)
        #expect(updated.addressesCheckedAt == now)
    }

    @Test func aServerWithoutTheListIsAskedAgainOnlyADayLater() async throws {
        let store = ConnectionStore(secrets: InMemorySecretStore())
        let connection = try pinned()
        try store.save(connection, token: "tok")

        await AddressRefresh.refresh(
            store: store, server: try FakeBrievieServer(), deviceID: connection.deviceID, at: Self.home, token: "tok"
        )

        let stored = try #require(try store.load())
        #expect(stored.connection.urls == connection.urls)
        #expect(stored.connection.addressesCheckedAt != nil)
        #expect(stored.token == "tok")
    }

    @Test func anAnswerWithoutUsableAddressesChangesNothing() throws {
        let answer = ServerAddresses(urls: ["http://plain.example.nl"], publicURLs: [])

        #expect(AddressRefresh.updated(try pinned(), with: answer, now: Date()) == nil)
    }
}
