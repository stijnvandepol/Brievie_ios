import BrievieAPI
import Foundation
import Testing

/// The client generated from the host's contract reads what the host really sends: nullable fields as
/// optionals, and timestamps with or without fractional seconds.
@Suite struct GeneratedContractTests {
    private static let workspaceID = "71673a98-9dd7-4023-a848-fea48b8aa912"
    private static let documentID = "d6311302-19ae-4d0b-ab51-a3bdde16e78a"

    private func document(letterDate: String, createdAt: String) -> String {
        """
        {"id":"\(Self.documentID)","client_id":"0b7f6b0e-6a5d-4c59-9d0e-0d6a3c3b9a11","status":"needs_review",
         "page_count":1,"created_at":"\(createdAt)","sender":"","document_type":"","letter_date":\(letterDate),
         "addressee_ids":[],"label_ids":[],"inbox_state":"new","open_suggestion_count":1,
         "suggestions":[{"id":"5c1e9f0a-2b3d-4e5f-8a6b-7c8d9e0f1a2b","action":"add_label",
                         "label_id":"9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d","person_id":null,"origin":"ai",
                         "rule_name":"","quote":"","confidence":"0.700","preselected":false}],
         "failure_code":"","summary":"","summary_by_ai":false,
         "pages":[{"index":1,"ocr_text":"tekst"}],"proposals":[],
         "tasks":[{"id":"8520f89b-c359-420c-b156-617624b31eb8","type":"pay","description":"Betalen",
                   "deadline":null,"deadline_source":"manual","deadline_quote":"","status":"open"}]}
        """
    }

    private func fetch(_ json: String) async throws -> Components.Schemas.DocumentOut {
        let url = try StubURLProtocol.serve(.response(status: 200, json: json))
        let session = URLSession(configuration: StubURLProtocol.configuration())
        defer { session.finishTasksAndInvalidate() }
        let client = APIClient.make(baseURL: url, session: session, token: "tok", maxJSONBytes: 1_024 * 1_024)
        let output = try await client.getDocument(
            path: .init(workspaceId: Self.workspaceID, documentId: Self.documentID)
        )
        return try output.ok.body.json
    }

    @Test func nullableFieldsAreOptionals() async throws {
        let without = try await fetch(document(letterDate: "null", createdAt: "2026-11-14T10:00:00Z"))
        let with = try await fetch(document(letterDate: #""2026-11-03""#, createdAt: "2026-11-14T10:00:00Z"))

        #expect(without.letterDate == nil)
        #expect(with.letterDate == "2026-11-03")
        #expect(without.tasks.first?.deadline == nil)
        #expect(without.suggestions?.first?.personId == nil)
        #expect(without.suggestions?.first?.labelId == "9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d")
    }

    @Test func documentFiltersAreOptionalQueryParameters() {
        // Every filter of `listDocuments` may be left out: the app asks for all documents that way.
        let none = Operations.ListDocuments.Input.Query()
        let some = Operations.ListDocuments.Input.Query(
            inboxState: "unassigned", personId: "3f0c8a52-6d0e-4c8e-9a51-1e2b3c4d5e6f"
        )

        #expect(none.inboxState == nil && none.personId == nil && none.labelId == nil)
        #expect(some.inboxState == "unassigned")
    }

    @Test(arguments: [
        "2026-11-14T10:00:00.123456Z",
        "2026-11-14T10:00:00.123Z",
        "2026-11-14T10:00:00Z",
        "2026-11-14T11:00:00.123456+01:00"
    ])
    func timestampsWithAndWithoutFractionsDecode(createdAt: String) async throws {
        let document = try await fetch(document(letterDate: "null", createdAt: createdAt))

        let expected = Date(timeIntervalSince1970: 1_794_650_400)
        #expect(abs(document.createdAt.timeIntervalSince(expected)) < 1)
    }

    @Test func uploadMetadataEncodesToTheContractNames() throws {
        let metadata = Components.Schemas.UploadMetadataIn(
            clientId: "0b7f6b0e-6a5d-4c59-9d0e-0d6a3c3b9a11",
            pages: [.init(sha256: String(repeating: "a", count: 64), text: "tekst")]
        )

        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata)) as? [String: Any]

        #expect(object?["client_id"] as? String == "0b7f6b0e-6a5d-4c59-9d0e-0d6a3c3b9a11")
        let pages = object?["pages"] as? [[String: String]]
        #expect(pages == [["sha256": String(repeating: "a", count: 64), "text": "tekst"]])
    }
}
