import BrievieAPI
@testable import BrievieCore
import Foundation
import Testing

/// Every request to the server says in which language the user reads, so the server answers in it.
@Suite struct AcceptLanguageTests {
    private let trust = ServerTrust(caCertificateDER: nil)

    @Test func listsThePreferredLanguagesInOrderWithDecreasingWeight() {
        #expect(AcceptLanguageHeader.value(preferred: ["en-GB"]) == "en-GB")
        #expect(AcceptLanguageHeader.value(preferred: ["nl-NL", "en-GB", "de-DE"]) == "nl-NL, en-GB;q=0.9, de-DE;q=0.8")
    }

    @Test func sendsAtMostFourLanguages() {
        let value = AcceptLanguageHeader.value(preferred: ["nl", "en", "de", "fr", "es", "it"])
        #expect(value == "nl, en;q=0.9, de;q=0.8, fr;q=0.7")
    }

    @Test func sendsNothingRatherThanAMalformedValue() {
        #expect(AcceptLanguageHeader.value(preferred: []) == nil)
        #expect(AcceptLanguageHeader.value(preferred: ["", "en\r\nX-Evil: 1", "<b>"]) == nil)
        #expect(AcceptLanguageHeader.value(preferred: ["en\r\nX-Evil: 1", "nl-NL"]) == "nl-NL")
    }

    @Test func everyApiRequestCarriesIt() async throws {
        let server = LiveBrievieServer(
            configuration: StubURLProtocol.configuration, acceptLanguage: { "en-GB, nl;q=0.9" }
        )
        let list = try StubURLProtocol.serve(.response(status: 200, json: "[]"))
        let health = try StubURLProtocol.serve(.response(status: 200, json: #"{"status":"ok","api_version":"1.0.0"}"#))

        _ = try await server.workspaces(at: list, trust: trust, token: "tok")
        _ = try await server.health(at: health, trust: trust)

        for url in [list, health] {
            let request = try #require(StubURLProtocol.requests(to: url).first)
            #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en-GB, nl;q=0.9")
        }
    }

    @Test func noLanguageMeansNoHeaderFromTheClient() async throws {
        let server = LiveBrievieServer(configuration: StubURLProtocol.configuration, acceptLanguage: { nil })
        let url = try StubURLProtocol.serve(.response(status: 200, json: #"{"status":"ok","api_version":"1.0.0"}"#))

        _ = try await server.health(at: url, trust: trust)

        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == nil)
    }

    @Test func aBackgroundUploadCarriesIt() throws {
        let upload = UploadRequest(
            itemID: UUID(), deviceID: UUID(), attemptID: UUID(),
            url: try #require(URL(string: "https://brievie.example.nl/api/v1/workspaces/x/documents")),
            bodyFile: URL(filePath: "/tmp/none"), boundary: "b", token: "tok", earliestBegin: nil
        )

        let request = BackgroundUploadTransport.request(for: upload, appVersion: nil, acceptLanguage: "en-GB")
        let bare = BackgroundUploadTransport.request(for: upload, appVersion: nil, acceptLanguage: nil)

        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en-GB")
        #expect(bare.value(forHTTPHeaderField: "Accept-Language") == nil)
    }
}
