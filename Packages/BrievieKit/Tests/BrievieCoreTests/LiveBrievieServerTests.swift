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
        (400, "something_else", ServerError.other("http_400")),
        (422, "validation_error", ServerError.other("validation_error")),
        (422, String(repeating: "x", count: 10_000), ServerError.other("http_422")),
        (413, "payload_too_large", ServerError.other("http_413")),
        (415, "unsupported_media_type", ServerError.other("http_415")),
        (429, "too_many_attempts", ServerError.tooManyAttempts),
        (401, "not_authenticated", ServerError.unauthorized),
        (500, "internal_error", ServerError.other("http_500"))
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

    @Test func unknownWorkspaceKindAndRoleDecodeAsUnknown() async throws {
        let url = try StubURLProtocol.serve(.response(
            status: 200, json: #"[{"id":"\#(Self.workspaceID)","name":"X","kind":"club","role":"owner"}]"#
        ))

        let workspaces = try await server.workspaces(at: url, trust: trust, token: "t")

        #expect(workspaces.map(\.kind) == [.unknown])
        #expect(workspaces.map(\.role) == [.unknown])
    }

    @Test func badWorkspaceIDIsIncompatible() async throws {
        let url = try StubURLProtocol.serve(.response(
            status: 200, json: #"[{"id":"not-a-uuid","name":"X","kind":"home","role":"admin"}]"#
        ))

        await #expect(throws: ServerError.incompatible) {
            try await server.workspaces(at: url, trust: trust, token: "t")
        }
    }

    // MARK: - revokeDevice

    @Test func revokeDeviceDeletesThisDeviceWithItsToken() async throws {
        let url = try StubURLProtocol.serve(.data(status: 204, contentType: "application/json", body: Data()))
        let deviceID = try #require(UUID(uuidString: "F5400FDE-D094-49BA-9B51-62596E6DF070"))

        try await server.revokeDevice(deviceID, at: url, trust: trust, token: "device-token-123")

        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path() == "/api/v1/devices/f5400fde-d094-49ba-9b51-62596e6df070")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer device-token-123")
    }

    @Test(arguments: [
        (401, "not_authenticated", ServerError.unauthorized),
        (404, "device_not_found", ServerError.other("device_not_found")),
        (404, "something_else", ServerError.other("http_404")),
        (403, "csrf_failed", ServerError.other("http_403")),
        (500, "internal_error", ServerError.other("http_500"))
    ])
    func revokeDeviceMapsRefusals(status: Int, code: String, expected: ServerError) async throws {
        let url = try StubURLProtocol.serve(.response(status: status, json: #"{"code":"\#(code)","message":"x"}"#))

        await #expect(throws: expected) {
            try await server.revokeDevice(UUID(), at: url, trust: trust, token: "device-token-123")
        }
    }

    // MARK: - redirects (the API never redirects)

    @Test func workspacesDoNotFollowRedirectsWithTheToken() async throws {
        let target = try StubURLProtocol.serve(.response(status: 200, json: "[]"))
        let url = try StubURLProtocol.serve(.redirect(target.appending(path: "api/v1/workspaces")))

        await #expect(throws: ServerError.other("http_302")) {
            try await server.workspaces(at: url, trust: trust, token: "device-token-123")
        }
        #expect(StubURLProtocol.requests(to: target).isEmpty)
    }

    @Test func pairDoesNotFollowRedirectsWithTheCode() async throws {
        let target = try StubURLProtocol.serve(.response(status: 201, json: "{}"))
        let url = try StubURLProtocol.serve(.redirect(target.appending(path: "api/v1/devices/pair")))

        await #expect(throws: ServerError.other("http_302")) {
            try await server.pair(at: url, trust: trust, code: "ABCD-EFGH", deviceName: "iPhone")
        }
        #expect(StubURLProtocol.requests(to: target).isEmpty)
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

    // MARK: - cancellation

    @Test func cancelledTaskThrowsCancellationNotUntrusted() async throws {
        let server = server
        let trust = trust
        let url = try StubURLProtocol.serve(.failure(.cancelled))
        let health = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await server.health(at: url, trust: trust)
        }
        let certificate = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await server.caCertificatePEM(at: url)
        }

        await #expect(throws: CancellationError.self) { try await health.value }
        await #expect(throws: CancellationError.self) { try await certificate.value }
    }
}

@Suite struct SessionConfigurationTests {
    @Test func hardenedSessionsTimeOutAndKeepNoState() {
        let configuration = SessionConfiguration.hardened(.ephemeral)

        #expect(configuration.timeoutIntervalForRequest == 15)
        #expect(configuration.timeoutIntervalForResource == 30)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.urlCache == nil)
        #expect(!configuration.httpShouldSetCookies)
    }
}
