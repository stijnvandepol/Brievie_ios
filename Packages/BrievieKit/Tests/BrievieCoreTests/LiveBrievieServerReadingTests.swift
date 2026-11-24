@testable import BrievieCore
import Foundation
import Testing

/// "Mijn post", "Ongelezen" and "Blijft liggen" (host PR #44) in `LiveBrievieServer`, against `StubURLProtocol`.
@Suite struct LiveBrievieServerReadingTests {
    private let server = LiveBrievieServer(configuration: StubURLProtocol.configuration)
    private static let workspaceID = UUID(uuidString: "71673A98-9DD7-4023-A848-FEA48B8AA912") ?? UUID()
    private static let documentID = UUID(uuidString: "D6311302-19AE-4D0B-AB51-A3BDDE16E78A") ?? UUID()
    private static let workspacePath = "/api/v1/workspaces/71673a98-9dd7-4023-a848-fea48b8aa912"
    private static let documentPath = "\(workspacePath)/documents/d6311302-19ae-4d0b-ab51-a3bdde16e78a"

    private static let summaryJSON = """
        "id":"d6311302-19ae-4d0b-ab51-a3bdde16e78a","client_id":"0b7f6b0e-6a5d-4c59-9d0e-0d6a3c3b9a11",
        "page_count":2,"created_at":"2026-11-14T10:00:00Z","sender":"Belastingdienst","status":"done",
        "document_type":"assessment","letter_date":null,"addressee_ids":[],"label_ids":[],"inbox_state":""
        """

    private func scope(_ url: URL) -> DocumentScope {
        DocumentScope(
            url: url, trust: ServerTrust(caCertificateDER: nil), token: "tok", workspaceID: Self.workspaceID
        )
    }

    @Test func menuCountsDecode() async throws {
        let json = """
            {"inbox":3,"my_post_unread":4,"my_tasks":2,"my_tasks_overdue":1,"lingering":5,
             "shows_lingering":true,"has_person":false}
            """
        let url = try StubURLProtocol.serve(.response(status: 200, json: json))

        let counts = try await server.menuCounts(in: scope(url))

        #expect(counts == MenuCounts(
            inbox: 3, myPostUnread: 4, myTasks: 2, myTasksOverdue: 1, lingering: 5, showsLingering: true,
            hasPerson: false
        ))
        #expect(StubURLProtocol.requests(to: url).first?.url?.path() == "\(Self.workspacePath)/menu/counts")
    }

    @Test func menuCountsLeftOutReadAsTheirDefaults() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: "{}"))

        #expect(try await server.menuCounts(in: scope(url)) == MenuCounts())
    }

    @Test func anOlderServerHasNoMenuCounts() async throws {
        let url = try StubURLProtocol.serve(.response(status: 404, json: #"{"detail":"Not Found"}"#))

        await #expect(throws: ServerError.other("http_404")) {
            try await server.menuCounts(in: scope(url))
        }
    }

    @Test func markReadAndUnreadUseOnePathWithTwoMethods() async throws {
        let read = try StubURLProtocol.serve(.data(status: 204, contentType: "application/json", body: Data()))
        let unread = try StubURLProtocol.serve(.data(status: 204, contentType: "application/json", body: Data()))

        try await server.markRead(Self.documentID, in: scope(read))
        try await server.markUnread(Self.documentID, in: scope(unread))

        let readRequest = try #require(StubURLProtocol.requests(to: read).first)
        let unreadRequest = try #require(StubURLProtocol.requests(to: unread).first)
        #expect(readRequest.httpMethod == "POST")
        #expect(unreadRequest.httpMethod == "DELETE")
        #expect(readRequest.url?.path() == "\(Self.documentPath)/read")
        #expect(unreadRequest.url?.path() == "\(Self.documentPath)/read")
    }

    @Test func markManyReadSendsTheIdsAndReadsTheCount() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: #"{"marked":1}"#))

        let marked = try await server.markRead([Self.documentID], in: scope(url))

        #expect(marked == 1)
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "\(Self.workspacePath)/documents/read")
        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["document_ids"] as? [String] == ["d6311302-19ae-4d0b-ab51-a3bdde16e78a"])
    }

    @Test func myPostAsksForTheOwnLettersOnly() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: "[{\(Self.summaryJSON),\"unread\":true}]"))

        let list = try await server.documents(in: scope(url), filter: DocumentFilter(addressedToMe: true))

        #expect(list.map(\.isUnread) == [true])
        let query = try #require(StubURLProtocol.requests(to: url).first?.url?.query())
        #expect(query.contains("addressed_to_me=true"))
        #expect(!query.contains("unread_only"))
    }

    @Test func anOrdinaryListSendsNoneOfTheNewParameters() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: "[{\(Self.summaryJSON)}]"))

        let list = try await server.documents(in: scope(url), filter: .all)

        #expect(list.map(\.isUnread) == [false])
        let query = StubURLProtocol.requests(to: url).first?.url?.query() ?? ""
        #expect(!query.contains("addressed_to_me") && !query.contains("unread_only"))
    }

    @Test func lingeringDecodesBothGroups() async throws {
        let json = """
            {"too_long_in_inbox":[{\(Self.summaryJSON),"days":4}],"not_opened":[],"inbox_days":2,
             "unopened_days":5}
            """
        let url = try StubURLProtocol.serve(.response(status: 200, json: json))

        let answer = try await server.lingeringLetters(in: scope(url))

        #expect(answer.tooLongInInbox.map(\.days) == [4])
        #expect(answer.tooLongInInbox.map(\.id) == [Self.documentID])
        #expect(answer.notOpened.isEmpty && answer.inboxDays == 2 && answer.unopenedDays == 5)
        #expect(StubURLProtocol.requests(to: url).first?.url?.path() == "\(Self.workspacePath)/inbox/lingering")
    }
}
