@testable import BrievieCore
import Foundation
import Testing

/// `LiveBrievieServer` against `StubURLProtocol`: the generated client, middleware and error mapping run for
/// real, only the network is replaced. (TLS trust is covered by `ServerTrustTests` and the live test.)
@Suite struct LiveBrievieServerTests {
    private let server = LiveBrievieServer(configuration: StubURLProtocol.configuration)
    private let trust = ServerTrust(caCertificateDER: nil)

    private static let workspaceID = "71673a98-9dd7-4023-a848-fea48b8aa912"

    // MARK: - health

    @Test func healthReturnsAPIVersion() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: #"{"status":"ok","api_version":"1.0.0"}"#))

        let version = try await server.health(at: url, trust: trust)

        #expect(version == "1.0.0")
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.url?.path() == "/api/v1/health")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func unexpectedBodyIsIncompatible() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: #"{"hello":"world"}"#))

        await #expect(throws: ServerError.incompatible) {
            try await server.health(at: url, trust: trust)
        }
    }

    // MARK: - pair

    @Test func pairSendsCodeAndNameAndReturnsDevice() async throws {
        let url = try StubURLProtocol.serve(.response(status: 201, json: """
            {"device_id":"f5400fde-d094-49ba-9b51-62596e6df070","token":"tok",
             "user":{"id":"a608ca19-5cb2-42cf-bb31-d601227c0efa","email":"beheer@brievie.local","name":"Beheerder",
                     "language":"nl","explanation_language":"nl"}}
            """))

        let device = try await server.pair(at: url, trust: trust, code: "ABCD-EFGH", deviceName: "iPhone van Stijn")

        #expect(device == PairedDevice(
            deviceID: try #require(UUID(uuidString: "f5400fde-d094-49ba-9b51-62596e6df070")),
            token: "tok",
            userName: "Beheerder"
        ))
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "/api/v1/devices/pair")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
        #expect(body == ["code": "ABCD-EFGH", "device_name": "iPhone van Stijn"])
    }

    @Test(arguments: [
        (400, "pairing_code_invalid", ServerError.invalidCode),
        (400, "something_else", ServerError.other("something_else")),
        (422, "validation_error", ServerError.other("validation_error")),
        (429, "too_many_attempts", ServerError.tooManyAttempts),
        (401, "not_authenticated", ServerError.unauthorized),
        (500, "server_error", ServerError.other("http_500"))
    ])
    func pairMapsRefusals(status: Int, code: String, expected: ServerError) async throws {
        let url = try StubURLProtocol.serve(.response(status: status, json: #"{"code":"\#(code)","message":"x"}"#))

        await #expect(throws: expected) {
            try await server.pair(at: url, trust: trust, code: "ABCD-EFGH", deviceName: "iPhone")
        }
    }

    // MARK: - workspaces

    @Test func workspacesSendBearerTokenAndMapKindAndRole() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: """
            [{"id":"\(Self.workspaceID)","name":"Thuis","kind":"home","role":"admin"},
             {"id":"\(Self.workspaceID)","name":"Zaak","kind":"business","role":"viewer"}]
            """))

        let workspaces = try await server.workspaces(at: url, trust: trust, token: "device-token-123")

        let id = try #require(UUID(uuidString: Self.workspaceID))
        #expect(workspaces == [
            WorkspaceSummary(id: id, name: "Thuis", kind: .home, role: .admin),
            WorkspaceSummary(id: id, name: "Zaak", kind: .business, role: .viewer)
        ])
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.url?.path() == "/api/v1/workspaces")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer device-token-123")
    }

    @Test func workspacesUnauthorized() async throws {
        let url = try StubURLProtocol.serve(
            .response(status: 401, json: #"{"code":"not_authenticated","message":"x"}"#)
        )

        await #expect(throws: ServerError.unauthorized) {
            try await server.workspaces(at: url, trust: trust, token: "revoked")
        }
    }

    @Test func unknownWorkspaceKindIsIncompatible() async throws {
        let url = try StubURLProtocol.serve(.response(
            status: 200, json: #"[{"id":"\#(Self.workspaceID)","name":"X","kind":"club","role":"admin"}]"#
        ))

        await #expect(throws: ServerError.incompatible) {
            try await server.workspaces(at: url, trust: trust, token: "t")
        }
    }

    // MARK: - transport failures

    @Test(arguments: [
        (URLError.Code.cannotConnectToHost, ServerError.unreachable),
        (.cannotFindHost, .unreachable),
        (.timedOut, .unreachable),
        (.notConnectedToInternet, .unreachable),
        (.networkConnectionLost, .unreachable),
        (.cancelled, .untrusted),
        (.serverCertificateUntrusted, .untrusted),
        (.serverCertificateHasUnknownRoot, .untrusted)
    ])
    func mapsTransportFailures(code: URLError.Code, expected: ServerError) async throws {
        let url = try StubURLProtocol.serve(.failure(code))

        await #expect(throws: expected) {
            try await server.health(at: url, trust: trust)
        }
        await #expect(throws: expected) {
            try await server.caCertificatePEM(at: url)
        }
    }
}

/// The one request made without trust: `GET /api/v1/server/ca-certificate`.
@Suite struct CACertificateDownloadTests {
    private let server = LiveBrievieServer(configuration: StubURLProtocol.configuration)

    @Test func returnsPEM() async throws {
        let pem = try Fixtures.text("ca.pem")
        let json = try #require(String(bytes: try JSONEncoder().encode(["pem": pem]), encoding: .utf8))
        let url = try StubURLProtocol.serve(.response(status: 200, json: json))

        #expect(try await server.caCertificatePEM(at: url) == pem)
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path() == "/api/v1/server/ca-certificate")
    }

    @Test func sendsNoCredentialsCookiesOrInheritedHeaders() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: #"{"pem":"x"}"#))
        let host = try #require(url.host())
        let cookie = try #require(HTTPCookie(properties: [.domain: host, .path: "/", .name: "sessionid", .value: "s"]))
        let leaky = LiveBrievieServer {
            let configuration = StubURLProtocol.configuration()
            configuration.httpAdditionalHeaders = ["Authorization": "Bearer leaked"]
            // An ephemeral configuration has its own in-memory cookie store.
            configuration.httpCookieStorage?.setCookie(cookie)
            configuration.httpShouldSetCookies = true
            return configuration
        }

        _ = try await leaky.caCertificatePEM(at: url)

        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    @Test func refusesOversizedResponse() async throws {
        let padding = String(repeating: "A", count: CACertificateDownload.maximumBytes)
        let url = try StubURLProtocol.serve(.response(status: 200, json: #"{"pem":"\#(padding)"}"#))

        await #expect(throws: ServerError.other("response_too_large")) {
            try await server.caCertificatePEM(at: url)
        }
    }

    @Test func doesNotFollowRedirects() async throws {
        let target = try StubURLProtocol.serve(.response(status: 200, json: #"{"pem":"from elsewhere"}"#))
        let url = try StubURLProtocol.serve(.redirect(target.appending(path: "api/v1/server/ca-certificate")))

        await #expect(throws: ServerError.other("http_302")) {
            try await server.caCertificatePEM(at: url)
        }
        #expect(StubURLProtocol.requests(to: target).isEmpty)
    }

    @Test func noPrivateCA() async throws {
        let url = try StubURLProtocol.serve(.response(status: 404, json: #"{"code":"no_private_ca","message":"x"}"#))

        await #expect(throws: ServerError.other("no_private_ca")) {
            try await server.caCertificatePEM(at: url)
        }
    }

    @Test func trustDecisionOnlyAcceptsServerTrustForTheRequestedHost() throws {
        let delegate = CACertificateDownload.Delegate(host: "localhost")
        let serverTrust = try Fixtures.serverTrust(leaf: "other-leaf.pem")

        #expect(delegate.disposition(
            authenticationMethod: NSURLAuthenticationMethodServerTrust, serverTrust: serverTrust, host: "localhost"
        ) == .useCredential)
        #expect(delegate.disposition(
            authenticationMethod: NSURLAuthenticationMethodServerTrust, serverTrust: serverTrust, host: "evil.example"
        ) == .cancelAuthenticationChallenge)
        #expect(delegate.disposition(
            authenticationMethod: NSURLAuthenticationMethodServerTrust, serverTrust: nil, host: "localhost"
        ) == .cancelAuthenticationChallenge)
        for method in [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodClientCertificate] {
            #expect(delegate.disposition(
                authenticationMethod: method, serverTrust: serverTrust, host: "localhost"
            ) == .cancelAuthenticationChallenge)
        }
    }
}
