@testable import BrievieCore
import Foundation
import Testing

/// A token the host expired after 180 idle days (host Task 9) behaves exactly like a revoked one: the host answers
/// both with `401 not_authenticated`, and the app forgets the pairing and explains on the pairing screen.
@MainActor
@Suite struct ExpiredTokenTests {
    /// The host's exact answer to an expired token.
    static let expiredBody = #"{"code":"not_authenticated","message":"Je bent niet ingelogd."}"#

    private let secrets = InMemorySecretStore()
    private var store: ConnectionStore { ConnectionStore(secrets: secrets) }

    @Test func theHostsExpiredTokenAnswerIsARevocation() async throws {
        let server = LiveBrievieServer(configuration: StubURLProtocol.configuration)
        let url = try StubURLProtocol.serve(.response(status: 401, json: Self.expiredBody))

        await #expect(throws: ServerError.unauthorized) {
            try await server.workspaces(at: url, trust: ServerTrust(caCertificateDER: nil), token: "expired")
        }
    }

    @Test func theSameAnswerOnAnUploadIsARevocation() {
        let item = UploadItem(
            id: UUID(), workspaceID: UUID(), deviceID: UUID(), createdAt: Date(timeIntervalSince1970: 0),
            pageCount: 1, bodyByteCount: 10, boundary: "b", state: .uploading, attempt: 0,
            urlIndex: 0, nextAttemptAt: nil, failureCode: nil
        )
        let body = Data(Self.expiredBody.utf8)
        let outcome = BackgroundUploadTransport.outcome(error: nil, status: 401, body: body, reasons: [])

        #expect(outcome == .status(401, code: "not_authenticated"))
        #expect(UploadPolicy.decide(outcome, item: item, urlCount: 1) == .revoked)
    }

    @Test func aRevokedAndAnExpiredDeviceEndOnTheSamePairingScreen() async throws {
        let connection = ServerConnection(
            urls: [try #require(URL(string: "https://brievie.example.nl"))], caCertificateDER: nil,
            deviceID: UUID(), userName: "Beheerder"
        )
        try store.save(connection, token: "expired-token")
        let model = AppModel(
            store: store, authenticator: FakeAuthenticator(),
            launchFlag: InMemoryLaunchFlag(hasLaunchedBefore: true), isProtectedDataAvailable: { true }
        )
        model.start()
        await model.unlock()

        model.sessionRevoked(deviceID: connection.deviceID)

        #expect(model.state == .unpaired(notice: AppStrings.sessionRevoked))
        #expect(try store.load() == nil)
        #expect(secrets.read(.deviceToken) == nil)
        #expect(secrets.read(.serverConnection) == nil)
    }

    @Test func theNoticeFitsBothCauses() {
        let notice = AppStrings.sessionRevoked

        #expect(notice.contains("Koppel dit toestel opnieuw"))
        #expect(notice.contains("ingetrokken"))
        #expect(notice.contains("lang niet gebruikt"))
        // The user did not unpair it: the text must not say so.
        #expect(!notice.contains("Dit apparaat is ontkoppeld"))
    }

    /// Another code is `http_401`; a JSON body without a code does not even decode (`incompatible`). Neither is the
    /// host's verdict on the device, so neither forgets the pairing.
    @Test(arguments: [
        (#"{"code":"login_required","message":"x"}"#, ServerError.other("http_401")),
        (#"{"message":"x"}"#, ServerError.incompatible)
    ])
    func aMissingCodeIsNotAnExpiry(body: String, expected: ServerError) async throws {
        let server = LiveBrievieServer(configuration: StubURLProtocol.configuration)
        let url = try StubURLProtocol.serve(.response(status: 401, json: body))

        await #expect(throws: expected) {
            try await server.workspaces(at: url, trust: ServerTrust(caCertificateDER: nil), token: "t")
        }
        #expect(expected != .unauthorized)
    }

    @Test func aProxyLoginPageIsNotAnExpiry() async throws {
        let server = LiveBrievieServer(configuration: StubURLProtocol.configuration)
        let url = try StubURLProtocol.serve(.data(status: 401, contentType: "text/html", body: Data("<html>".utf8)))

        await #expect(throws: ServerError.other("http_401")) {
            try await server.workspaces(at: url, trust: ServerTrust(caCertificateDER: nil), token: "t")
        }
        let item = UploadItem(
            id: UUID(), workspaceID: UUID(), deviceID: UUID(), createdAt: Date(timeIntervalSince1970: 0),
            pageCount: 1, bodyByteCount: 10, boundary: "b", state: .uploading, attempt: 0,
            urlIndex: 0, nextAttemptAt: nil, failureCode: nil
        )
        #expect(UploadPolicy.decide(.status(401, code: nil), item: item, urlCount: 1) != .revoked)
    }
}
