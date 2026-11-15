@testable import BrievieCore
import Foundation
import Testing

@Suite struct UploadPolicyTests {
    private func item(attempt: Int = 0, urlIndex: Int = 0) -> UploadItem {
        UploadItem(
            id: UUID(), workspaceID: UUID(), deviceID: UUID(), createdAt: Date(timeIntervalSince1970: 0),
            pageCount: 1, bodyByteCount: 10, boundary: "b", state: .uploading, attempt: attempt,
            urlIndex: urlIndex, nextAttemptAt: nil, failureCode: nil
        )
    }

    private func decide(
        _ outcome: UploadOutcome, attempt: Int = 0, urlIndex: Int = 0, urls: Int = 1
    ) -> UploadDecision {
        UploadPolicy.decide(outcome, item: item(attempt: attempt, urlIndex: urlIndex), urlCount: urls)
    }

    @Test(arguments: [200, 201])
    func storedOnTheServerIsDone(status: Int) {
        // 200: the server already had this document (the first answer got lost; Review Focus 2).
        #expect(decide(.status(status, code: nil)) == .done)
    }

    @Test func unreachableTriesTheNextURLAtOnce() {
        #expect(decide(.unreachable, urlIndex: 0, urls: 2) == .retry(urlIndex: 1, after: .zero))
    }

    @Test func unreachableOnTheLastURLStartsOverWithBackoff() {
        #expect(decide(.unreachable, attempt: 0, urlIndex: 1, urls: 2) == .retry(urlIndex: 0, after: .seconds(30)))
        #expect(decide(.unreachable, attempt: 1, urlIndex: 0, urls: 1) == .retry(urlIndex: 0, after: .seconds(120)))
    }

    @Test func aLostAnswerRetriesTheSameItem() {
        // The request was sent, the connection dropped: same id and body again; the server answers 200.
        #expect(decide(.unreachable, urls: 1) == .retry(urlIndex: 0, after: .seconds(30)))
    }

    @Test(arguments: [429, 500, 502, 503, 504])
    func busyServerRetriesTheSameURLWithBackoff(status: Int) {
        let decision = decide(.status(status, code: "server_unavailable"), attempt: 2, urlIndex: 1, urls: 2)

        #expect(decision == .retry(urlIndex: 1, after: .seconds(600)))
    }

    @Test func backoffNeverExceedsOneHour() {
        for attempt in 0..<50 {
            guard case let .retry(_, after) = decide(.status(503, code: nil), attempt: attempt) else {
                Issue.record("expected a retry")
                return
            }
            #expect(after <= .seconds(3600))
        }
        #expect(decide(.status(503, code: nil), attempt: 49) == .retry(urlIndex: 0, after: .seconds(3600)))
    }

    @Test func revokedDeviceIsNotAFailure() {
        #expect(decide(.status(401, code: "not_authenticated")) == .revoked)
    }

    @Test(arguments: [
        (UploadOutcome.status(409, code: "document_conflict"), "document_conflict"),
        (.status(404, code: "workspace_not_found"), "workspace_not_found"),
        (.status(404, code: nil), "http_404"),
        (.status(422, code: "page_checksum_mismatch"), "page_checksum_mismatch"),
        (.status(422, code: "validation_error"), "validation_error"),
        (.status(413, code: "payload_too_large"), "payload_too_large"),
        (.status(411, code: "length_required"), "length_required"),
        (.status(415, code: "unsupported_media_type"), "http_415"),
        (.status(403, code: "forbidden"), "http_403"),
        (.status(400, code: "<script>alert(1)</script>"), "http_400"),
        (.status(418, code: String(repeating: "x", count: 5000)), "http_418")
    ])
    func clientErrorsFailWithACodeFromAClosedSet(outcome: UploadOutcome, expected: String) {
        #expect(decide(outcome) == .failed(code: expected))
    }

    @Test func uploadWithoutAPairingIsPausedNotFailed() {
        #expect(decide(.unpaired) == .paused)
    }

    @Test func untrustedServerFailsInsteadOfWaiting() {
        #expect(decide(.untrusted) == .failed(code: "untrusted"))
    }

    @Test func unexpectedStatusRetriesWithBackoff() {
        // A proxy page, a redirect that was refused: not our server's verdict on the document.
        #expect(decide(.status(302, code: nil)) == .retry(urlIndex: 0, after: .seconds(30)))
    }
}
