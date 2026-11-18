@testable import BrievieCore
import Foundation
import Testing

/// The 1d contract is additive: this app keeps working against a 1c server (no proof path, no new fields), and
/// reads a 1d server's extra fields without needing them. A failure here means a new field was made required.
@Suite struct OneCServerCompatibilityTests {
    private let server = LiveBrievieServer(configuration: StubURLProtocol.configuration, appVersion: "1.4.0 (12)")
    private let trust = ServerTrust(caCertificateDER: nil)

    private static let oneCPairOut = """
        {"device_id":"f5400fde-d094-49ba-9b51-62596e6df070","token":"tok",
         "user":{"id":"a608ca19-5cb2-42cf-bb31-d601227c0efa","email":"beheer@brievie.local","name":"Beheerder",
                 "language":"nl","explanation_language":"nl"}}
        """
    private static let workspaceID = "71673a98-9dd7-4023-a848-fea48b8aa912"

    @Test func aOneCPairAnswerWithoutTheNewFieldsDecodes() async throws {
        let url = try StubURLProtocol.serve(.response(status: 201, json: Self.oneCPairOut))

        let device = try await server.pair(at: url, trust: trust, code: "ABCD-EFGH", deviceName: "iPhone")

        #expect(device.userName == "Beheerder")
        #expect(device.token == "tok")
    }

    @Test func aOneCWorkspaceListDecodes() async throws {
        let url = try StubURLProtocol.serve(.response(
            status: 200, json: #"[{"id":"\#(Self.workspaceID)","name":"Thuis","kind":"home","role":"admin"}]"#
        ))

        let workspaces = try await server.workspaces(at: url, trust: trust, token: "t")

        #expect(workspaces.map(\.role) == [.admin])
    }

    @Test func aOneDAnswerWithExtraFieldsDecodes() async throws {
        let pairURL = try StubURLProtocol.serve(.response(status: 201, json: """
            {"device_id":"f5400fde-d094-49ba-9b51-62596e6df070","token":"tok","future":{"x":1},
             "user":{"id":"a608ca19-5cb2-42cf-bb31-d601227c0efa","email":"b@x.nl","name":"Beheerder",
                     "language":"nl","explanation_language":"nl","is_server_admin":true,"sso":"oidc"}}
            """))
        let listURL = try StubURLProtocol.serve(.response(status: 200, json: """
            [{"id":"\(Self.workspaceID)","name":"Zaak","kind":"business","role":"owner","member_count":3}]
            """))

        let device = try await server.pair(at: pairURL, trust: trust, code: "ABCD-EFGH", deviceName: "iPhone")
        let workspaces = try await server.workspaces(at: listURL, trust: trust, token: "t")

        #expect(device.userName == "Beheerder")
        #expect(workspaces.map(\.role) == [.unknown])
        #expect(workspaces.map(\.kind) == [.business])
    }

    @Test func theVersionHeaderAndBodyFieldAreHarmlessToAOneCServer() async throws {
        // A 1c server ignores headers and body keys it does not know: it answers as before.
        let url = try StubURLProtocol.serve(.response(status: 201, json: Self.oneCPairOut))

        let device = try await server.pair(at: url, trust: trust, code: "ABCD-EFGH", deviceName: "iPhone")

        #expect(device.token == "tok")
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.value(forHTTPHeaderField: "X-Brievie-App-Version") == "1.4.0 (12)")
    }

    @Test func qrPairingWorksAgainstAOneCServer() async throws {
        let harness = try PairingHarness()

        _ = try await harness.pair()

        #expect(try harness.store.load() != nil)
        #expect(!harness.server.calls.contains { $0.isChallenge || $0.isProof })
    }

    @Test func linkPairingAgainstAServerWithoutTheProofPathSendsNoCode() async throws {
        let harness = try PairingHarness()
        harness.server.challenge = { _ in throw ServerError.other("http_404") }
        let link = try Self.link(harness)
        let code = try #require(PairingCode(typed: "ABCD-2345"))

        await #expect(throws: PairingError.incompatibleServer) {
            try await harness.service.pair(link: link, code: code, deviceName: "iPhone")
        }

        try harness.expectNothingStored()
        #expect(!harness.server.calls.contains { $0.isPair || $0.isProof })
        #expect(!harness.server.calls.contains { String(describing: $0).contains("ABCD") })
    }

    @Test(arguments: ["1.0.0", "1.4.2"])
    func anyOneXServerIsSupported(version: String) async throws {
        let harness = try PairingHarness()
        harness.server.health = { _ in version }
        let code = try #require(PairingCode(typed: "ABCD-2345"))

        _ = try await harness.service.pair(link: try Self.link(harness), code: code, deviceName: "iPhone")

        #expect(try harness.store.load() != nil)
    }

    @Test func aTwoXServerIsIncompatible() async throws {
        let harness = try PairingHarness()
        harness.server.health = { _ in "2.0.0" }
        let code = try #require(PairingCode(typed: "ABCD-2345"))

        await #expect(throws: PairingError.incompatibleServer) {
            try await harness.service.pair(link: try Self.link(harness), code: code, deviceName: "iPhone")
        }

        try harness.expectNothingStored()
        #expect(!harness.server.calls.contains { $0.isChallenge || $0.isProof || $0.isPair })
    }

    /// The harness's two addresses with its CA pin, as a 1d server's link names them.
    private static func link(_ harness: PairingHarness) throws -> ServerLink {
        let pin = try Fixtures.text("ca.sha256").trimmingCharacters(in: .whitespacesAndNewlines)
        let urls = [harness.home, harness.away].map { url in
            "url=" + (url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
        }
        let fragment = (["v=1"] + urls + ["ca_sha256=\(pin)", "pairing=0b7e2f4c-5d1a-4e8b-9c3f-6a2d8e1f4b70"])
            .joined(separator: "&")
        return try ServerLink.parse(try #require(URL(string: "brievie://server#" + fragment)))
    }
}
