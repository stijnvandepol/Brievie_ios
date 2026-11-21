@testable import BrievieCore
import Foundation
import Testing

/// The trash calls of `LiveBrievieServer` (trash, restore, list) against `StubURLProtocol`, and how their errors
/// reach a screen through `WorkspaceDocuments`.
@Suite struct LiveBrievieServerTrashTests {
    private let server = LiveBrievieServer(configuration: StubURLProtocol.configuration)
    private static let workspaceID = UUID(uuidString: "71673A98-9DD7-4023-A848-FEA48B8AA912") ?? UUID()
    private static let documentID = UUID(uuidString: "D6311302-19AE-4D0B-AB51-A3BDDE16E78A") ?? UUID()
    private static let workspacePath = "/api/v1/workspaces/71673a98-9dd7-4023-a848-fea48b8aa912"
    private static let documentPath = "\(workspacePath)/documents/d6311302-19ae-4d0b-ab51-a3bdde16e78a"

    static func trashedJSON(
        id: String = "d6311302-19ae-4d0b-ab51-a3bdde16e78a", trashedByName: String? = "Anna"
    ) -> String {
        let name = trashedByName.map { #","trashed_by_name":"\#($0)""# } ?? ""
        return """
            {"id":"\(id)","client_id":"0b7f6b0e-6a5d-4c59-9d0e-0d6a3c3b9a11",
             "status":"done","page_count":1,"created_at":"2026-11-14T10:00:00Z","sender":"CAK",
             "document_type":"invoice","letter_date":"2026-11-03",
             "trashed_at":"2026-11-21T09:30:00Z","purge_after":"2026-12-21T09:30:00Z"\(name)}
            """
    }

    private static let documentJSON = """
        {"id":"d6311302-19ae-4d0b-ab51-a3bdde16e78a","client_id":"0b7f6b0e-6a5d-4c59-9d0e-0d6a3c3b9a11",
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

    @Test func trashPostsAndDecodesTheTrashedLetter() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.trashedJSON()))

        let trashed = try await server.trash(Self.documentID, in: scope(url))

        #expect(trashed.id == Self.documentID)
        #expect(trashed.summary.sender == "CAK")
        #expect(trashed.summary.letterDate == CalendarDate(year: 2026, month: 11, day: 3))
        #expect(trashed.trashedAt == Date(timeIntervalSince1970: 1_795_253_400))
        #expect(trashed.purgeAfter == Date(timeIntervalSince1970: 1_797_845_400))
        #expect(trashed.trashedByName == "Anna")
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "\(Self.documentPath)/trash")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }

    @Test func aTrashAnswerWithoutTrashedByNameIsEmpty() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.trashedJSON(trashedByName: nil)))

        let trashed = try await server.trash(Self.documentID, in: scope(url))

        #expect(trashed.trashedByName.isEmpty)
    }

    @Test func restorePostsAndReturnsTheLetter() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.documentJSON))

        let detail = try await server.restore(Self.documentID, in: scope(url))

        #expect(detail.summary.id == Self.documentID)
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "\(Self.documentPath)/restore")
    }

    @Test func trashListDecodesItemsRetentionAndTotal() async throws {
        let second = Self.trashedJSON(id: "3c5d7e9f-1a2b-4c3d-8e4f-5a6b7c8d9e0f", trashedByName: "")
        let url = try StubURLProtocol.serve(.response(status: 200, json: """
            {"items":[\(Self.trashedJSON()),\(second)],"retention_days":30,"total":3}
            """))

        let list = try await server.trashList(in: scope(url))

        #expect(list.items.count == 2)
        #expect(list.retentionDays == 30)
        #expect(list.total == 3)
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path() == "\(Self.workspacePath)/trash")
    }

    @Test func aTrashListWithoutTotalCountsItsItems() async throws {
        let second = Self.trashedJSON(id: "3c5d7e9f-1a2b-4c3d-8e4f-5a6b7c8d9e0f")
        let url = try StubURLProtocol.serve(.response(status: 200, json: """
            {"items":[\(Self.trashedJSON()),\(second)]}
            """))

        let list = try await server.trashList(in: scope(url))

        #expect(list.total == 2)
        #expect(list.retentionDays == 30)
    }

    @Test func aLetterInTheTrashAnswersInTrash() async throws {
        let body = #"{"code":"document_in_trash","message":"Deze brief staat in de prullenbak."}"#
        let url = try StubURLProtocol.serve(.response(status: 404, json: body))

        await #expect(throws: DocumentsError.inTrash) { try await documents(url).detail(Self.documentID) }
    }

    @Test func forbiddenMapsToForbidden() async throws {
        let body = #"{"code":"forbidden","message":"Je mag dit niet doen in deze werkruimte."}"#
        let url = try StubURLProtocol.serve(.response(status: 403, json: body))

        await #expect(throws: DocumentsError.forbidden) { try await documents(url).trash(Self.documentID) }
    }

    @Test func aServerWithoutATrashIsNotSupported() async throws {
        let url = try StubURLProtocol.serve(.response(status: 404, json: #"{"detail":"Not Found"}"#))

        await #expect(throws: DocumentsError.notSupported) { try await documents(url).trashList() }
    }
}
