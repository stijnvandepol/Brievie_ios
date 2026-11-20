@testable import BrievieCore
import Foundation
import Testing

/// What the AI did by itself (host, autopilot): `confirmed_by_ai`, `auto_label_ids`, `auto_addressee_ids` on a
/// document and `created_by_ai` on a task. All optional in the contract: an older server leaves them out.
@Suite struct LiveBrievieServerAutomaticTests {
    private let server = LiveBrievieServer(configuration: StubURLProtocol.configuration)
    private static let labelID = "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d"
    private static let personID = "3f0c8a52-6d0e-4c8e-9a51-1e2b3c4d5e6f"

    private static let summaryJSON = """
        "id":"d6311302-19ae-4d0b-ab51-a3bdde16e78a","client_id":"0b7f6b0e-6a5d-4c59-9d0e-0d6a3c3b9a11",
        "page_count":1,"created_at":"2026-11-14T10:00:00Z","sender":"Wonen Voorbeeld","document_type":"other",
        "status":"done","letter_date":null,"inbox_state":"sorted","open_suggestion_count":0,
        "addressee_ids":["\(personID)"],"label_ids":["\(labelID)"]
        """

    private func scope(_ url: URL) -> DocumentScope {
        DocumentScope(url: url, trust: ServerTrust(caCertificateDER: nil), token: "tok", workspaceID: UUID())
    }

    @Test func aListEntryCarriesTheAutomaticMarks() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: """
            [{\(Self.summaryJSON),"confirmed_by_ai":true,"auto_label_ids":["\(Self.labelID)"],
              "auto_addressee_ids":["\(Self.personID)"]}]
            """))

        let document = try #require(try await server.documents(in: scope(url)).first)

        #expect(document.confirmedByAI)
        #expect(document.autoLabelIDs == [try #require(UUID(uuidString: Self.labelID))])
        #expect(document.autoAddresseeIDs == [try #require(UUID(uuidString: Self.personID))])
        #expect(document.isAutomatic)
    }

    @Test func anOlderServerMarksNothing() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: "[{\(Self.summaryJSON)}]"))

        let document = try #require(try await server.documents(in: scope(url)).first)

        #expect(!document.confirmedByAI)
        #expect(document.autoLabelIDs.isEmpty)
        #expect(document.autoAddresseeIDs.isEmpty)
        #expect(!document.isAutomatic)
    }

    @Test func aTaskTheAIMadeSaysSo() async throws {
        let task = """
            {"id":"8520f89b-c359-420c-b156-617624b31eb8","type":"pay","description":"Betalen","deadline":null,
             "deadline_source":"manual","deadline_quote":"","status":"open"
            """
        let url = try StubURLProtocol.serve(.response(status: 200, json: """
            {\(Self.summaryJSON),"failure_code":"","summary":"","summary_by_ai":false,"pages":[],"proposals":[],
             "suggestions":[],"tasks":[\(task),"created_by_ai":true},\(task.replacingOccurrences(
                of: "8520f89b", with: "9520f89b"))}]}
            """))

        let detail = try await server.document(UUID(), in: scope(url))

        #expect(detail.tasks.map(\.createdByAI) == [true, false])
    }

    @Test func anAutomaticLabelAloneMarksTheLetter() {
        let document = DocumentSummary(
            id: UUID(), clientID: UUID(), status: .done, pageCount: 1, createdAt: Date(), sender: "", documentType: "",
            letterDate: nil, autoLabelIDs: [UUID()]
        )

        #expect(document.isAutomatic)
    }

    @Test func aLetterToCheckCarriesTheProposedSender() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: """
            [{\(Self.summaryJSON),"proposed_sender":"Wonen Voorbeeld","proposed_document_type":"other",
              "proposed_letter_date":"2026-11-06"},{\(Self.summaryJSON)}]
            """))

        let documents = try await server.documents(in: scope(url))

        #expect(documents.map(\.proposedSender) == ["Wonen Voorbeeld", ""])
    }
}
