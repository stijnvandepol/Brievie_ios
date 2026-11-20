@testable import BrievieCore
import Foundation
import Testing

/// `searchDocuments` against `StubURLProtocol`: the term only in the POST body, hits with their fragment, and the
/// answers a screen must tell apart (429, a server without search).
@Suite struct LiveBrievieServerSearchTests {
    private let server = LiveBrievieServer(configuration: StubURLProtocol.configuration)
    private static let workspaceID = UUID(uuidString: "71673A98-9DD7-4023-A848-FEA48B8AA912") ?? UUID()
    private static let path = "/api/v1/workspaces/71673a98-9dd7-4023-a848-fea48b8aa912/documents/search"

    private static let hitJSON = """
        {"id":"d6311302-19ae-4d0b-ab51-a3bdde16e78a","client_id":"0b7f6b0e-6a5d-4c59-9d0e-0d6a3c3b9a11",
         "status":"done","page_count":1,"created_at":"2026-11-14T10:00:00Z","sender":"Waterbedrijf Voorbeeld",
         "document_type":"invoice","letter_date":null,"inbox_state":"sorted","addressee_ids":[],"label_ids":[],
         "snippet":[{"text":"Uw ","hit":false},{"text":"waterrekening","hit":true}]}
        """

    private func scope(_ url: URL) -> DocumentScope {
        DocumentScope(
            url: url, trust: ServerTrust(caCertificateDER: nil), token: "tok", workspaceID: Self.workspaceID
        )
    }

    @Test func postsTheTermInTheBodyAndMapsTheHits() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: """
            {"items":[\(Self.hitJSON)],"next_offset":30,"fuzzy":true,"bsn_removed":true}
            """))

        let page = try await server.search(DocumentSearchQuery(text: "water rekening", offset: 0), in: scope(url))

        let hit = try #require(page.hits.first)
        #expect(hit.document.sender == "Waterbedrijf Voorbeeld")
        #expect(hit.snippet == [
            SnippetPart(text: "Uw ", isHit: false), SnippetPart(text: "waterrekening", isHit: true)
        ])
        #expect(page.nextOffset == 30)
        #expect(page.isFuzzy)
        #expect(page.bsnRemoved)

        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == Self.path)
        #expect(request.url?.query() == nil)
        let body = try #require(request.httpBody)
        let sent = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(sent["q"] as? String == "water rekening")
        #expect(sent["offset"] as? Int == 0)
        #expect(sent["limit"] as? Int == DocumentSearchQuery.pageSize)
    }

    @Test func anOlderAnswerWithoutTheNewFieldsStillReads() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: """
            {"items":[],"next_offset":null}
            """))

        let page = try await server.search(DocumentSearchQuery(text: "brief"), in: scope(url))

        #expect(page == DocumentSearchPage(hits: []))
    }

    @Test func tooManySearchesIsToldApart() async throws {
        let url = try StubURLProtocol.serve(.response(status: 429, json: """
            {"code":"rate_limited","message":"Even wachten."}
            """))

        await #expect(throws: ServerError.tooManyAttempts) {
            try await server.search(DocumentSearchQuery(text: "brief"), in: scope(url))
        }
    }

    /// A server before host PR #27: its catch-all 404 for a path it lacks.
    @Test func aServerWithoutSearchAnswers404() async throws {
        let url = try StubURLProtocol.serve(.response(status: 404, json: """
            {"code":"not_found","message":"Deze pagina bestaat niet."}
            """))

        await #expect(throws: ServerError.other("http_404")) {
            try await server.search(DocumentSearchQuery(text: "brief"), in: scope(url))
        }
    }
}
