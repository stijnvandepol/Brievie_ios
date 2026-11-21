@testable import BrievieCore
import Foundation
import Testing

/// The duplicate calls of `LiveBrievieServer` (list, get, merge, dismiss) against `StubURLProtocol`, and how their
/// errors reach a screen through `WorkspaceDocuments`.
@Suite struct LiveBrievieServerDuplicatesTests {
    private let server = LiveBrievieServer(configuration: StubURLProtocol.configuration)
    private static let workspaceID = UUID(uuidString: "71673A98-9DD7-4023-A848-FEA48B8AA912") ?? UUID()
    private static let pairID = UUID(uuidString: "5A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D") ?? UUID()
    private static let firstID = UUID(uuidString: "D6311302-19AE-4D0B-AB51-A3BDDE16E78A") ?? UUID()
    private static let secondID = UUID(uuidString: "E7422413-2ABF-4E1C-BC62-B4CEEF27F89B") ?? UUID()
    private static let pairsPath = "/api/v1/workspaces/71673a98-9dd7-4023-a848-fea48b8aa912/duplicates"

    private static func summaryJSON(_ id: String, sender: String) -> String {
        """
        {"id":"\(id)","client_id":"0b7f6b0e-6a5d-4c59-9d0e-0d6a3c3b9a11","status":"done","page_count":1,
         "created_at":"2026-11-14T10:00:00Z","sender":"\(sender)","document_type":"invoice",
         "letter_date":"2026-11-03","open_duplicate_count":1}
        """
    }

    private static let basePairJSON = """
        "id":"5a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d","state":"open","created_at":"2026-11-20T10:00:00Z",
        "first":\(summaryJSON("d6311302-19ae-4d0b-ab51-a3bdde16e78a", sender: "Gemeente Voorbeelddorp")),
        "second":\(summaryJSON("e7422413-2abf-4e1c-bc62-b4ceef27f89b", sender: "Gemeente Voorbeelddorp")),
        "suggested_keep_id":"e7422413-2abf-4e1c-bc62-b4ceef27f89b","text_similarity":92
        """

    private static let fullPairJSON = """
        {\(basePairJSON),"same":["sender"],
         "differences":[{"field":"amount","first":"120.50","second":"125.00","uncertain":true},
                        {"field":"colour","first":"rood","second":"blauw"}],
         "task_twins":[{"done_document_id":"d6311302-19ae-4d0b-ab51-a3bdde16e78a",
                        "open_document_id":"e7422413-2abf-4e1c-bc62-b4ceef27f89b","type":"pay",
                        "description":"Betaal de aanslag"}],
         "can_merge":true,"blocked_reason":""}
        """

    private static let documentJSON = """
        {"id":"e7422413-2abf-4e1c-bc62-b4ceef27f89b","client_id":"0b7f6b0e-6a5d-4c59-9d0e-0d6a3c3b9a11",
         "status":"done","page_count":1,"created_at":"2026-11-14T10:00:00Z","sender":"CAK","document_type":"bill",
         "letter_date":null,"failure_code":"","summary":"","summary_by_ai":false,"pages":[],"proposals":[],
         "tasks":[]}
        """

    private func scope(_ url: URL) -> DocumentScope {
        DocumentScope(
            url: url, trust: ServerTrust(caCertificateDER: nil), token: "tok", workspaceID: Self.workspaceID
        )
    }

    private func documents(_ url: URL) throws -> WorkspaceDocuments {
        let store = ConnectionStore(secrets: InMemorySecretStore())
        let connection = ServerConnection(urls: [url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn")
        try store.save(connection, token: "tok")
        return WorkspaceDocuments(workspaceID: Self.workspaceID, connection: connection, store: store, server: server)
    }

    private func refusal(_ status: Int, _ code: String) throws -> URL {
        try StubURLProtocol.serve(.response(status: status, json: #"{"code":"\#(code)","message":"x"}"#))
    }

    @Test func listDuplicatesDecodesAPair() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: "[\(Self.fullPairJSON)]"))

        let pairs = try await server.duplicates(in: scope(url))

        let pair = try #require(pairs.first)
        #expect(pairs.count == 1)
        #expect(pair.id == Self.pairID)
        #expect(pair.createdAt == Date(timeIntervalSince1970: 1_795_168_800))
        #expect(pair.first.id == Self.firstID)
        #expect(pair.second.id == Self.secondID)
        #expect(pair.first.sender == "Gemeente Voorbeelddorp")
        #expect(pair.suggestedKeepID == Self.secondID)
        #expect(pair.similarity == 92)
        #expect(pair.same == [.sender])
        #expect(pair.differences == [
            DuplicateDifference(field: .amount, first: "120.50", second: "125.00", isUncertain: true)
        ])
        #expect(pair.taskTwins == [
            TaskTwin(
                doneDocumentID: Self.firstID, openDocumentID: Self.secondID, type: "pay",
                description: "Betaal de aanslag"
            )
        ])
        #expect(pair.canMerge)
        #expect(pair.blockedReason.isEmpty)
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path() == Self.pairsPath)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }

    @Test func anUnknownDifferenceFieldIsDropped() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.fullPairJSON))

        let pair = try await server.duplicate(Self.pairID, in: scope(url))

        #expect(pair.differences.map(\.field) == [.amount])
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.url?.path() == "\(Self.pairsPath)/5a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d")
    }

    @Test func aPairWithoutTheNewerFieldsUsesDefaults() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: "{\(Self.basePairJSON)}"))

        let pair = try await server.duplicate(Self.pairID, in: scope(url))

        #expect(pair.same.isEmpty)
        #expect(pair.differences.isEmpty)
        #expect(pair.taskTwins.isEmpty)
        #expect(pair.canMerge)
        #expect(pair.blockedReason.isEmpty)
    }

    @Test(arguments: [(-5, 0), (0, 0), (100, 100), (140, 100)])
    func theSimilarityStaysWithinAHundred(sent: Int, kept: Int) async throws {
        let json = "{\(Self.basePairJSON)}".replacingOccurrences(
            of: #""text_similarity":92"#, with: #""text_similarity":\#(sent)"#
        )
        let url = try StubURLProtocol.serve(.response(status: 200, json: json))

        #expect(try await server.duplicate(Self.pairID, in: scope(url)).similarity == kept)
    }

    @Test func mergeSendsTheKeptLetterAndTheTwinChoice() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.documentJSON))

        let kept = try await server.mergeDuplicate(
            Self.pairID, keep: Self.secondID, completeTwinTasks: false, in: scope(url)
        )

        #expect(kept.summary.id == Self.secondID)
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "\(Self.pairsPath)/5a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d/merge")
        let body = try #require(request.httpBody)
        let sent = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(sent.count == 2)
        #expect(sent["keep_document_id"] as? String == "e7422413-2abf-4e1c-bc62-b4ceef27f89b")
        #expect(sent["complete_twin_tasks"] as? Bool == false)
    }

    @Test func dismissPostsAndAcceptsNoContent() async throws {
        let url = try StubURLProtocol.serve(.data(status: 204, contentType: "application/json", body: Data()))

        try await server.dismissDuplicate(Self.pairID, in: scope(url))

        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "\(Self.pairsPath)/5a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d/dismiss")
    }

    @Test func notOpenMapsToAlreadyDecided() async throws {
        let documents = try documents(refusal(409, "duplicate_not_open"))

        await #expect(throws: DocumentsError.alreadyDecided) { try await documents.dismissDuplicate(Self.pairID) }
    }

    @Test func visibilityDiffersMapsToVisibilityDiffers() async throws {
        let documents = try documents(refusal(409, "duplicate_visibility_differs"))

        await #expect(throws: DocumentsError.visibilityDiffers) {
            try await documents.mergeDuplicate(Self.pairID, keep: Self.firstID, completeTwinTasks: true)
        }
    }

    @Test func aGonePairIsNotFound() async throws {
        let documents = try documents(refusal(404, "duplicate_not_found"))

        await #expect(throws: DocumentsError.notFound) { try await documents.duplicate(Self.pairID) }
    }

    @Test func aViewerMergeIsForbidden() async throws {
        let documents = try documents(refusal(403, "forbidden"))

        await #expect(throws: DocumentsError.forbidden) {
            try await documents.mergeDuplicate(Self.pairID, keep: Self.firstID, completeTwinTasks: true)
        }
    }

    @Test func aRetainedLetterIsAPlainFailure() async throws {
        let documents = try documents(refusal(409, "document_retained"))

        await #expect(throws: DocumentsError.failed) {
            try await documents.mergeDuplicate(Self.pairID, keep: Self.firstID, completeTwinTasks: true)
        }
    }

    @Test func aServerWithoutPairsIsNotSupported() async throws {
        let documents = try documents(StubURLProtocol.serve(.response(status: 404, json: #"{"detail":"Not Found"}"#)))

        await #expect(throws: DocumentsError.notSupported) { try await documents.duplicates() }
    }

    // MARK: - The duplicate count on letters and in the inbox counts

    private static let letterJSON = """
        "id":"d6311302-19ae-4d0b-ab51-a3bdde16e78a","client_id":"0b7f6b0e-6a5d-4c59-9d0e-0d6a3c3b9a11",
        "status":"done","page_count":1,"created_at":"2026-11-14T10:00:00Z","sender":"CAK",
        "document_type":"bill","letter_date":null
        """

    @Test func aSummaryWithoutTheDuplicateCountHasNone() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: "[{\(Self.letterJSON)}]"))

        let summary = try #require(try await server.documents(in: scope(url)).first)

        #expect(summary.openDuplicateCount == 0)
        #expect(!summary.isPossibleDuplicate)
    }

    @Test func aSummaryWithAnOpenPairIsAPossibleDuplicate() async throws {
        let url = try StubURLProtocol.serve(
            .response(status: 200, json: #"[{\#(Self.letterJSON),"open_duplicate_count":1}]"#)
        )

        let summary = try #require(try await server.documents(in: scope(url)).first)

        #expect(summary.openDuplicateCount == 1)
        #expect(summary.isPossibleDuplicate)
    }

    @Test func aLetterCarriesItsDuplicateCount() async throws {
        let json = #"{\#(Self.letterJSON),"open_duplicate_count":2,"failure_code":"","summary":"","#
            + #""summary_by_ai":false,"pages":[],"proposals":[],"tasks":[]}"#
        let url = try StubURLProtocol.serve(.response(status: 200, json: json))

        let detail = try await server.document(Self.firstID, in: scope(url))

        #expect(detail.summary.openDuplicateCount == 2)
    }

    @Test func countsWithoutDuplicateAreZero() async throws {
        let without = try StubURLProtocol.serve(.response(status: 200, json: #"{"new":2,"review":1,"unassigned":0}"#))
        let with = try StubURLProtocol.serve(
            .response(status: 200, json: #"{"new":2,"review":1,"unassigned":0,"duplicate":2}"#)
        )

        #expect(try await server.inboxCounts(in: scope(without)).duplicate == 0)
        #expect(try await server.inboxCounts(in: scope(with)).duplicate == 2)
    }
}
