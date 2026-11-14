@testable import BrievieCore
import Foundation
import Security
import Testing

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

    @Test func unknownErrorCodeIsNotPassedThrough() async throws {
        let url = try StubURLProtocol.serve(.response(status: 404, json: #"{"code":"pwned <script>","message":"x"}"#))

        await #expect(throws: ServerError.other("http_404")) {
            try await server.caCertificatePEM(at: url)
        }
    }

    @Test func trustDecisionOnlyAcceptsServerTrustForTheRequestedHost() throws {
        let serverTrust = try Fixtures.serverTrust(leaf: "other-leaf.pem")
        func decide(_ method: String, _ trust: SecTrust?, _ host: String) -> URLSession.AuthChallengeDisposition {
            CACertificateDownload.disposition(
                authenticationMethod: method, serverTrust: trust, challengeHost: host, requestedHost: "localhost"
            )
        }

        #expect(decide(NSURLAuthenticationMethodServerTrust, serverTrust, "localhost") == .useCredential)
        #expect(decide(NSURLAuthenticationMethodServerTrust, serverTrust, "LOCALHOST") == .useCredential)
        #expect(
            decide(NSURLAuthenticationMethodServerTrust, serverTrust, "evil.example") == .cancelAuthenticationChallenge
        )
        #expect(decide(NSURLAuthenticationMethodServerTrust, nil, "localhost") == .cancelAuthenticationChallenge)
        for method in [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodClientCertificate] {
            #expect(decide(method, serverTrust, "localhost") == .cancelAuthenticationChallenge)
        }
    }
}
