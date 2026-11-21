@testable import BrievieCore
import Foundation
import Testing

/// A task's amount and who has it on the letter: what the confirm sends and the detail reads.
@Suite struct LiveBrievieServerTaskAmountTests {
    private let server = LiveBrievieServer(configuration: StubURLProtocol.configuration)
    private static let workspaceID = UUID(uuidString: "71673A98-9DD7-4023-A848-FEA48B8AA912") ?? UUID()
    private static let documentID = UUID(uuidString: "D6311302-19AE-4D0B-AB51-A3BDDE16E78A") ?? UUID()

    private static func detailJSON(tasks: String = "[]") -> String {
        """
        {"id":"d6311302-19ae-4d0b-ab51-a3bdde16e78a","client_id":"0b7f6b0e-6a5d-4c59-9d0e-0d6a3c3b9a11",
         "status":"done","page_count":1,"created_at":"2026-11-14T10:00:00Z","sender":"CAK","document_type":"bill",
         "letter_date":null,"failure_code":"","summary":"","summary_by_ai":false,"pages":[],"proposals":[],
         "tasks":\(tasks)}
        """
    }

    private func scope(_ url: URL) -> DocumentScope {
        DocumentScope(
            url: url, trust: ServerTrust(caCertificateDER: nil), token: "tok", workspaceID: Self.workspaceID
        )
    }

    @Test func confirmSendsTheAmountAsADecimalString() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.detailJSON()))
        let task = { (amount: String) in
            TaskDraft(
                type: "pay", description: "Betalen", deadline: nil, deadlineSource: "manual", deadlineQuote: "",
                needsAttention: false, amount: amount
            )
        }
        let review = ConfirmedReview(
            sender: "CAK", documentType: "bill", letterDate: nil, summary: "", summaryByAI: false,
            tasks: [task("1234.5"), task(""), task("1.234,56")]
        )

        _ = try await server.confirm(Self.documentID, review: review, in: scope(url))

        let sent = try #require(StubURLProtocol.requests(to: url).first?.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: sent) as? [String: Any])
        let tasks = try #require(body["tasks"] as? [[String: Any]])
        // Only the API's own form goes out: the review converts the user's notation before this.
        #expect(tasks.map { $0["amount"] as? String } == ["1234.50", "", ""])
    }
}
