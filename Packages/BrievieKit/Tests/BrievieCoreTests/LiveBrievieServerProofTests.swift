@testable import BrievieCore
import Foundation
import Testing

/// `createPairingChallenge` and `pairDeviceWithProof` through the generated client, against `StubURLProtocol`.
@Suite struct LiveBrievieServerProofTests {
    private let server = LiveBrievieServer(configuration: StubURLProtocol.configuration, appVersion: "1.4.0 (12)")
    private let trust = ServerTrust(caCertificateDER: nil)
    private static let pairingID = "0b7e2f4c-5d1a-4e8b-9c3f-6a2d8e1f4b70"
    private static let nonce = FakeBrievieServer.nonce
    private static let proof = String(repeating: "0a", count: 32)
    private static let challengeOut = #"{"nonce":"\#(nonce)","expires_at":"2026-11-18T10:00:00Z"}"#

    @Test func challengeAndProofHitTheContractPaths() async throws {
        let challengeURL = try StubURLProtocol.serve(.response(status: 201, json: Self.challengeOut))
        let proofURL = try StubURLProtocol.serve(.response(status: 201, json: AppVersionTests.pairOut))
        let pairingID = try #require(UUID(uuidString: Self.pairingID))

        let nonce = try await server.pairingChallenge(at: challengeURL, trust: trust)
        let device = try await server.pairWithProof(
            at: proofURL, trust: trust, proof: CodeProof(pairingID: pairingID, nonce: nonce, proof: Self.proof),
            deviceName: "iPhone"
        )

        #expect(nonce == Self.nonce)
        #expect(device.token == "tok")
        let challenge = try #require(StubURLProtocol.requests(to: challengeURL).first)
        #expect(challenge.httpMethod == "POST")
        #expect(challenge.url?.path() == "/api/v1/devices/pairing-challenges")
        #expect(challenge.value(forHTTPHeaderField: "Authorization") == nil)
        let sent = try #require(StubURLProtocol.requests(to: proofURL).first)
        #expect(sent.httpMethod == "POST")
        #expect(sent.url?.path() == "/api/v1/devices/pair-with-proof")
        #expect(sent.url?.query() == nil)
        let body = try JSONSerialization.jsonObject(with: try #require(sent.httpBody)) as? [String: String]
        #expect(body == [
            "pairing_id": Self.pairingID, "nonce": Self.nonce, "proof": Self.proof, "device_name": "iPhone",
            "app_version": "1.4.0 (12)"
        ])
    }

    @Test(arguments: ["", "has space", "slash/", String(repeating: "a", count: 65), "née"])
    func aNonceThatIsNotOneIsIncompatible(nonce: String) async throws {
        let json = try #require(String(
            bytes: try JSONSerialization.data(withJSONObject: ["nonce": nonce, "expires_at": "2026-11-18T10:00:00Z"]),
            encoding: .utf8
        ))
        let url = try StubURLProtocol.serve(.response(status: 201, json: json))

        await #expect(throws: ServerError.incompatible) {
            try await server.pairingChallenge(at: url, trust: trust)
        }
    }

    @Test(arguments: [
        (404, "not_found", ServerError.other("http_404")),
        (429, "too_many_requests", ServerError.tooManyAttempts),
        (500, "internal_error", ServerError.other("http_500"))
    ])
    func challengeRefusals(status: Int, code: String, expected: ServerError) async throws {
        let url = try StubURLProtocol.serve(.response(status: status, json: #"{"code":"\#(code)","message":"x"}"#))

        await #expect(throws: expected) {
            try await server.pairingChallenge(at: url, trust: trust)
        }
    }

    @Test(arguments: [
        (400, "pairing_code_invalid", ServerError.invalidCode),
        (400, "pairing_challenge_invalid", ServerError.invalidCode),
        (400, "something_else", ServerError.other("http_400")),
        (422, "validation_error", ServerError.other("validation_error")),
        (429, "too_many_attempts", ServerError.tooManyAttempts),
        (404, "not_found", ServerError.other("http_404"))
    ])
    func proofRefusals(status: Int, code: String, expected: ServerError) async throws {
        let url = try StubURLProtocol.serve(.response(status: status, json: #"{"code":"\#(code)","message":"x"}"#))
        let pairingID = try #require(UUID(uuidString: Self.pairingID))

        await #expect(throws: expected) {
            try await server.pairWithProof(
                at: url, trust: trust, proof: CodeProof(pairingID: pairingID, nonce: Self.nonce, proof: Self.proof),
                deviceName: "iPhone"
            )
        }
    }

    /// The whole link path over the generated client: no request URL, header or body holds the typed code.
    @Test func theCodeIsInNoRequestOnTheLinkPath() async throws {
        let pem = try Fixtures.text("ca.pem")
        let pemJSON = try #require(String(bytes: try JSONEncoder().encode(["pem": pem]), encoding: .utf8))
        let url = try StubURLProtocol.serve(.routes([
            "/api/v1/server/ca-certificate": .response(status: 200, json: pemJSON),
            "/api/v1/health": .response(status: 200, json: #"{"status":"ok","api_version":"1.0.0"}"#),
            "/api/v1/devices/pairing-challenges": .response(status: 201, json: Self.challengeOut),
            "/api/v1/devices/pair-with-proof": .response(status: 201, json: AppVersionTests.pairOut)
        ]))
        let pin = try Fixtures.text("ca.sha256").trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded = try #require(url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let link = try ServerLink.parse(try #require(URL(
            string: "brievie://server#v=1&url=\(encoded)&ca_sha256=\(pin)&pairing=\(Self.pairingID)&code=ZZZZ-ZZZZ"
        )))
        let store = ConnectionStore(secrets: InMemorySecretStore())
        let code = try #require(PairingCode(typed: "abcd-2345"))

        _ = try await PairingService(server: server, store: store).pair(link: link, code: code, deviceName: "iPhone")

        let requests = StubURLProtocol.requests(to: url)
        #expect(requests.compactMap { $0.url?.path() } == [
            "/api/v1/server/ca-certificate", "/api/v1/health", "/api/v1/devices/pairing-challenges",
            "/api/v1/devices/pair-with-proof"
        ])
        for request in requests {
            let headers = (request.allHTTPHeaderFields ?? [:]).map { "\($0.key): \($0.value)" }.joined(separator: "\n")
            let body = request.httpBody.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
            let everything = [request.url?.absoluteString ?? "", headers, body].joined(separator: "\n").uppercased()
            for secret in ["ABCD2345", "ABCD-2345", "ABCD 2345", "ZZZZ"] {
                #expect(!everything.contains(secret), "\(request.url?.path() ?? "") carries \(secret)")
            }
        }
        #expect(try store.load()?.token == "tok")
    }
}
