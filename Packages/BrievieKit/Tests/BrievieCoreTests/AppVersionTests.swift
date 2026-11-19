import BrievieAPI
@testable import BrievieCore
import Foundation
import Testing

/// Every request to a paired server says which app version sent it (`X-Brievie-App-Version`, D 7.1).
@Suite struct AppVersionTests {
    private static let version = "1.4.0 (12)"
    private let trust = ServerTrust(caCertificateDER: nil)

    @Test func joinsShortVersionAndBuild() {
        #expect(AppVersionHeader.value(shortVersion: "1.4.0", build: "12") == "1.4.0 (12)")
    }

    @Test(arguments: [
        (nil, "1"), ("1.0", nil), ("", "1"), ("1.0", ""), ("<script>", "1"), ("1.0\r\nX-Evil: 1", "1"),
        (String(repeating: "1", count: 50), "1"), ("1.0", "1é")
    ] as [(String?, String?)])
    func refusesWhatTheServerWouldIgnore(short: String?, build: String?) {
        #expect(AppVersionHeader.value(shortVersion: short, build: build) == nil)
    }

    @Test func readsTheBundleKeys() throws {
        // The test bundle has no version keys: nothing rather than a guess.
        #expect(AppVersionHeader.current(bundle: Bundle(for: BundleToken.self)) == nil)
    }

    @Test func everyApiRequestCarriesTheVersion() async throws {
        let server = LiveBrievieServer(configuration: StubURLProtocol.configuration, appVersion: Self.version)
        let list = try StubURLProtocol.serve(.response(status: 200, json: "[]"))
        let health = try StubURLProtocol.serve(.response(status: 200, json: #"{"status":"ok","api_version":"1.0.0"}"#))

        _ = try await server.workspaces(at: list, trust: trust, token: "tok")
        _ = try await server.health(at: health, trust: trust)

        let listed = try #require(StubURLProtocol.requests(to: list).first)
        #expect(listed.value(forHTTPHeaderField: AppVersionHeader.name) == Self.version)
        #expect(listed.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        let checked = try #require(StubURLProtocol.requests(to: health).first)
        #expect(checked.value(forHTTPHeaderField: AppVersionHeader.name) == Self.version)
        #expect(checked.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func noVersionMeansNoHeader() async throws {
        let server = LiveBrievieServer(configuration: StubURLProtocol.configuration, appVersion: nil)
        let url = try StubURLProtocol.serve(.response(status: 200, json: #"{"status":"ok","api_version":"1.0.0"}"#))

        _ = try await server.health(at: url, trust: trust)

        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.value(forHTTPHeaderField: AppVersionHeader.name) == nil)
    }

    @Test func pairingSendsTheVersionInTheBodyAndTheHeader() async throws {
        let server = LiveBrievieServer(configuration: StubURLProtocol.configuration, appVersion: Self.version)
        let url = try StubURLProtocol.serve(.response(status: 201, json: Self.pairOut))

        _ = try await server.pair(at: url, trust: trust, code: "ABCD-EFGH", deviceName: "iPhone")

        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.value(forHTTPHeaderField: AppVersionHeader.name) == Self.version)
        let body = try JSONSerialization.jsonObject(with: try #require(request.httpBody)) as? [String: String]
        #expect(body == ["code": "ABCD-EFGH", "device_name": "iPhone", "app_version": Self.version])
    }

    @Test func aBackgroundUploadCarriesTheVersion() throws {
        let upload = UploadRequest(
            itemID: UUID(), deviceID: UUID(), attemptID: UUID(),
            url: try #require(URL(string: "https://brievie.example.nl/api/v1/workspaces/x/documents")),
            bodyFile: URL(filePath: "/tmp/none"), boundary: "b", token: "tok", earliestBegin: nil
        )

        let request = BackgroundUploadTransport.request(for: upload, appVersion: Self.version)
        let bare = BackgroundUploadTransport.request(for: upload, appVersion: nil)

        #expect(request.httpMethod == "POST")
        #expect(request.url == upload.url)
        #expect(request.value(forHTTPHeaderField: AppVersionHeader.name) == Self.version)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == MultipartBodyWriter.contentType(boundary: "b"))
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(bare.value(forHTTPHeaderField: AppVersionHeader.name) == nil)
        #expect(bare.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }

    @Test func theCACertificateRequestCarriesNoVersion() async throws {
        let server = LiveBrievieServer(configuration: StubURLProtocol.configuration, appVersion: Self.version)
        let url = try StubURLProtocol.serve(.response(status: 200, json: #"{"pem":"x"}"#))

        _ = try await server.caCertificatePEM(at: url)

        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.value(forHTTPHeaderField: AppVersionHeader.name) == nil)
    }

    static let pairOut = """
        {"device_id":"f5400fde-d094-49ba-9b51-62596e6df070","token":"tok",
         "user":{"id":"a608ca19-5cb2-42cf-bb31-d601227c0efa","email":"beheer@brievie.local","name":"Beheerder",
                 "language":"nl","explanation_language":"nl"}}
        """
}

private final class BundleToken {}
