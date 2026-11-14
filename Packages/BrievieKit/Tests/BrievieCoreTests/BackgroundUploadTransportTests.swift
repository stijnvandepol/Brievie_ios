@testable import BrievieCore
import Foundation
import Testing

/// The parts of the background transport that need no network.
@Suite struct BackgroundUploadTransportTests {
    private struct NoPairing: UploadTrustProvider {
        func currentTrust() -> ServerTrust? { nil }
    }

    @Test func configurationKeepsUploadingInTheBackgroundWithoutState() {
        let configuration = BackgroundUploadTransport.configuration(identifier: "test-\(UUID().uuidString)")

        #expect(configuration.sessionSendsLaunchEvents)
        #expect(!configuration.isDiscretionary)
        #expect(configuration.timeoutIntervalForResource == 7 * 24 * 60 * 60)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.urlCache == nil)
    }

    @Test func answerWithAStatusCarriesTheErrorCode() {
        let body = Data(#"{"code": "document_conflict", "message": "x"}"#.utf8)

        #expect(outcome(status: 409, body: body) == .status(409, code: "document_conflict"))
        #expect(outcome(status: 201) == .status(201, code: nil))
        #expect(outcome(status: 502, body: Data("<html>".utf8)) == .status(502, code: nil))
    }

    @Test func cancellationAfterOurTrustRefusalIsUntrusted() {
        #expect(outcome(error: URLError(.cancelled), trustRefused: true) == .untrusted)
    }

    @Test func otherCancellationIsUnreachableNotUntrusted() {
        // The system cancels background uploads when the user swipes the app away.
        #expect(outcome(error: URLError(.cancelled)) == .unreachable)
    }

    @Test func ourOwnCancelIsReportedAsSuch() {
        #expect(outcome(error: URLError(.cancelled), cancelledByApp: true) == .cancelledByUser)
    }

    @Test(arguments: [URLError.Code.serverCertificateUntrusted, .secureConnectionFailed, .serverCertificateHasBadDate])
    func certificateErrorsAreUntrusted(code: URLError.Code) {
        #expect(outcome(error: URLError(code)) == .untrusted)
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut, .cannotFindHost, .networkConnectionLost])
    func networkErrorsAreUnreachable(code: URLError.Code) {
        #expect(outcome(error: URLError(code)) == .unreachable)
    }

    @Test func withoutAReadablePairingTheServerIsRefused() throws {
        // Never a fallback to the system's trust for a server that should be pinned.
        let serverTrust = try Fixtures.serverTrust(leaf: "leaf-a.pem")

        let disposition = BackgroundUploadTransport.disposition(
            authenticationMethod: NSURLAuthenticationMethodServerTrust, serverTrust: serverTrust, host: "localhost",
            trust: NoPairing().currentTrust()
        )

        #expect(disposition == .cancelAuthenticationChallenge)
    }

    @Test func pinnedServerIsAcceptedAndAnotherIsRefused() throws {
        let trust = ServerTrust(caCertificateDER: try Fixtures.der("ca.pem"))
        func decide(_ leaf: String) throws -> URLSession.AuthChallengeDisposition {
            BackgroundUploadTransport.disposition(
                authenticationMethod: NSURLAuthenticationMethodServerTrust,
                serverTrust: try Fixtures.serverTrust(leaf: leaf), host: "localhost", trust: trust
            )
        }

        #expect(try decide("leaf-a.pem") == .useCredential)
        #expect(try decide("other-leaf.pem") == .cancelAuthenticationChallenge)
    }

    @Test func otherChallengesGetDefaultHandling() {
        let disposition = BackgroundUploadTransport.disposition(
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic, serverTrust: nil, host: "x", trust: nil
        )

        #expect(disposition == .performDefaultHandling)
    }

    @Test func taskDescriptionCarriesItemAndDevice() {
        let item = UUID()
        let device = UUID()

        let ids = BackgroundUploadTransport.ids(
            from: BackgroundUploadTransport.description(itemID: item, deviceID: device)
        )

        #expect(ids?.itemID == item)
        #expect(ids?.deviceID == device)
        #expect(BackgroundUploadTransport.ids(from: "iets anders") == nil)
        #expect(BackgroundUploadTransport.ids(from: nil) == nil)
    }

    @Test func uploadURLIsTheDocumentsEndpointOfTheWorkspace() throws {
        let base = try #require(URL(string: "https://brievie.local:8443"))
        let workspace = try #require(UUID(uuidString: "71673A98-9DD7-4023-A848-FEA48B8AA912"))

        let url = BackgroundUploadTransport.uploadURL(base: base, workspaceID: workspace)

        #expect(url.absoluteString
            == "https://brievie.local:8443/api/v1/workspaces/71673a98-9dd7-4023-a848-fea48b8aa912/documents")
    }

    @Test func storedPairingGivesItsPin() throws {
        let store = ConnectionStore(secrets: InMemorySecretStore())
        let provider = StoredConnectionTrustProvider(store: store)
        #expect(provider.currentTrust() == nil)

        let connection = ServerConnection(
            urls: [try #require(URL(string: "https://brievie.local"))], caCertificateDER: try Fixtures.der("ca.pem"),
            deviceID: UUID(), userName: "Stijn"
        )
        try store.save(connection, token: "tok")

        let trust = try #require(provider.currentTrust())
        #expect(trust.evaluate(try Fixtures.serverTrust(leaf: "leaf-a.pem"), host: "localhost"))
        #expect(!trust.evaluate(try Fixtures.serverTrust(leaf: "other-leaf.pem"), host: "localhost"))
    }

    private func outcome(
        error: (any Error)? = nil, status: Int? = nil, body: Data = Data(), trustRefused: Bool = false,
        cancelledByApp: Bool = false
    ) -> UploadOutcome {
        BackgroundUploadTransport.outcome(
            error: error, status: status, body: body, trustRefused: trustRefused, cancelledByApp: cancelledByApp
        )
    }
}
