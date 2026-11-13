@testable import BrievieCore
import Foundation
import Testing

/// Successful pairings, including the ones that only succeed at a later URL (Review Focus 2 and 4).
@Suite struct PairingServiceTests {
    private let harness: PairingHarness
    private var server: FakeBrievieServer { harness.server }
    private var home: URL { harness.home }
    private var away: URL { harness.away }

    init() throws {
        harness = try PairingHarness()
    }

    // MARK: - Happy path

    @Test func pairsAndStoresConnectionAndToken() async throws {
        let connection = try await harness.pair(name: "iPhone van Stijn")

        let expected = ServerConnection(
            urls: [home, away],
            caCertificateDER: try Fixtures.der("ca.pem"),
            deviceID: FakeBrievieServer.device.deviceID,
            userName: FakeBrievieServer.device.userName
        )
        #expect(connection == expected)
        let stored = try #require(try harness.store.load())
        #expect(stored.connection == expected)
        #expect(stored.token == FakeBrievieServer.device.token)
        #expect(server.calls == [
            .caCertificate(home), .health(home), .pair(home, code: "ABCD-EFGH", name: "iPhone van Stijn")
        ])
    }

    @Test func healthAndPairUseTrustPinnedToTheVerifiedCA() async throws {
        _ = try await harness.pair()

        let trusts = server.trusts
        #expect(trusts.count == 2)
        for trust in trusts {
            #expect(trust.evaluate(try Fixtures.serverTrust(leaf: "leaf-a.pem"), host: "localhost"))
            #expect(!trust.evaluate(try Fixtures.serverTrust(leaf: "other-leaf.pem"), host: "localhost"))
        }
    }

    @Test(arguments: ["1.0.0", "1.7.3"])
    func acceptsAnyVersionOne(apiVersion: String) async throws {
        server.health = { _ in apiVersion }

        _ = try await harness.pair()

        #expect(try harness.store.load() != nil)
    }

    @Test func withoutCAFingerprintSkipsCAFetchAndUsesSystemTrust() async throws {
        let connection = try await harness.service.pair(try harness.payload(caSHA256: nil), deviceName: "iPhone")

        #expect(server.calls.filter(\.isCACertificate).isEmpty)
        #expect(server.calls.first == .health(home))
        #expect(connection.caCertificateDER == nil)
        #expect(try harness.store.load()?.connection.caCertificateDER == nil)
        // System trust: the privately signed fixture leaf is refused.
        let trust = try #require(server.trusts.first)
        #expect(!trust.evaluate(try Fixtures.serverTrust(leaf: "leaf-a.pem"), host: "localhost"))
    }

    // MARK: - An unverifiable home URL moves on to the next one

    /// Ways the first URL can answer without being the paired Brievie server.
    enum Unverifiable: String, CaseIterable, Sendable {
        case otherCA, malformedPEM, caNotFound, caUndecodable, healthUntrusted, healthUndecodable, healthRefused

        func caAnswer(ourCA: String, otherCA: String) throws -> String {
            switch self {
            case .otherCA: otherCA
            case .malformedPEM: "not a certificate"
            case .caNotFound: throw ServerError.other("http_404")
            case .caUndecodable: throw ServerError.incompatible
            default: ourCA
            }
        }

        func healthAnswer() throws -> String {
            switch self {
            case .healthUntrusted: throw ServerError.untrusted
            case .healthUndecodable: throw ServerError.incompatible
            case .healthRefused: throw ServerError.unauthorized
            default: "1.0.0"
            }
        }
    }

    @Test(arguments: Unverifiable.allCases)
    func unverifiableHomeMovesToAwayWithoutSendingTheCode(_ failure: Unverifiable) async throws {
        let home = home
        let otherCA = try Fixtures.text("other-ca.pem")
        let ourCA = try Fixtures.text("ca.pem")
        server.caPEM = { url in
            url == home ? try failure.caAnswer(ourCA: ourCA, otherCA: otherCA) : ourCA
        }
        server.health = { url in
            url == home ? try failure.healthAnswer() : "1.0.0"
        }

        let connection = try await harness.pair()

        #expect(connection.urls == [home, away])
        #expect(try harness.store.load()?.connection.caCertificateDER == (try Fixtures.der("ca.pem")))
        #expect(server.calls.filter(\.isPair) == [.pair(away, code: "ABCD-EFGH", name: "iPhone")])
    }

    @Test func homeFingerprintMismatchOnlyCostsTheCACall() async throws {
        let home = home
        let otherCA = try Fixtures.text("other-ca.pem")
        let ourCA = try Fixtures.text("ca.pem")
        server.caPEM = { url in url == home ? otherCA : ourCA }

        _ = try await harness.pair()

        #expect(server.calls == [
            .caCertificate(home), .caCertificate(away), .health(away), .pair(away, code: "ABCD-EFGH", name: "iPhone")
        ])
        #expect(try harness.store.load() != nil)
    }

    @Test func unreachableCAFetchMovesToNextURL() async throws {
        let home = home
        let ourCA = try Fixtures.text("ca.pem")
        server.caPEM = { url in
            if url == home { throw ServerError.unreachable }
            return ourCA
        }

        let connection = try await harness.pair()

        #expect(connection.urls == [home, away])
        #expect(try harness.store.load()?.connection.urls == [home, away])
        #expect(server.calls == [
            .caCertificate(home), .caCertificate(away), .health(away), .pair(away, code: "ABCD-EFGH", name: "iPhone")
        ])
    }

    @Test func unreachableHealthMovesToNextURL() async throws {
        let home = home
        server.health = { url in
            if url == home { throw ServerError.unreachable }
            return "1.0.0"
        }

        let connection = try await harness.pair()

        #expect(connection.urls == [home, away])
        #expect(try harness.store.load()?.connection.urls == [home, away])
        #expect(server.calls.last == .pair(away, code: "ABCD-EFGH", name: "iPhone"))
    }
}
