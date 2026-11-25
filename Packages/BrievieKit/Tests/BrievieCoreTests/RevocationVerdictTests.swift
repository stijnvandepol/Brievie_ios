@testable import BrievieCore
import Foundation
import Testing

/// Only the Brievie server's own 401 (`not_authenticated`, what the host answers for a revoked or unknown device
/// token) means "this device is revoked": the app then forgets the pairing and removes the calendars. A 401
/// from something in front of it (a reverse proxy with its own login) is not that verdict.
@Suite struct RevocationVerdictTests {
    private let server = LiveBrievieServer(configuration: StubURLProtocol.configuration)
    private let trust = ServerTrust(caCertificateDER: nil)

    @Test func theHostsCodeIsARevocation() {
        #expect(ServerError(status: 401, code: "not_authenticated") == .unauthorized)
    }

    /// The host's 401 for an account that must set up two-step verification first: blocked, not revoked.
    @Test func secondFactorRequiredIsNoRevocation() {
        #expect(ServerError(status: 401, code: "second_factor_required") == .other("second_factor_required"))
    }

    @Test(arguments: [nil, "invalid_credentials", "proxy_login"] as [String?])
    func anyOther401IsNot(code: String?) {
        #expect(ServerError(status: 401, code: code) == .other("http_401"))
    }

    @Test func aProxys401WithoutABrievieBodyIsNotARevocation() async throws {
        let url = try StubURLProtocol.serve(.data(
            status: 401, contentType: "text/html", body: Data("<h1>Log in</h1>".utf8)
        ))

        await #expect(throws: ServerError.other("http_401")) {
            try await server.workspaces(at: url, trust: trust, token: "device-token")
        }
    }

    @Test func theHostsBodyOnA401IsARevocation() async throws {
        let url = try StubURLProtocol.serve(
            .response(status: 401, json: #"{"code":"not_authenticated","message":"Je bent niet ingelogd."}"#)
        )

        await #expect(throws: ServerError.unauthorized) {
            try await server.workspaces(at: url, trust: trust, token: "device-token")
        }
    }

    @Test func anUploadAnswered401WithoutTheHostsCodeIsNotARevocation() {
        let item = UploadItem(
            id: UUID(), workspaceID: UUID(), deviceID: UUID(), createdAt: Date(timeIntervalSince1970: 0),
            pageCount: 1, bodyByteCount: 10, boundary: "b", state: .uploading, attempt: 0, urlIndex: 0,
            nextAttemptAt: nil, failureCode: nil
        )

        let decision = UploadPolicy.decide(.status(401, code: nil), item: item, urlCount: 1)

        #expect(decision != .revoked)
        #expect(decision == .retry(urlIndex: 0, after: .seconds(30)))
        #expect(UploadPolicy.decide(.status(401, code: "not_authenticated"), item: item, urlCount: 1) == .revoked)
    }
}
