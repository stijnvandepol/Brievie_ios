@testable import BrievieCore
import Foundation
import Testing

/// The task calls of `LiveBrievieServer` (list open, complete, reopen) against `StubURLProtocol`.
@Suite struct LiveBrievieServerTasksTests {
    private let server = LiveBrievieServer(configuration: StubURLProtocol.configuration)
    private static let workspaceID = UUID(uuidString: "71673A98-9DD7-4023-A848-FEA48B8AA912") ?? UUID()
    private static let taskID = UUID(uuidString: "2B4C6D8E-0F1A-4B3C-9D5E-7F8A9B0C1D2E") ?? UUID()
    private static let documentID = "d6311302-19ae-4d0b-ab51-a3bdde16e78a"
    private static let tasksPath = "/api/v1/workspaces/71673a98-9dd7-4023-a848-fea48b8aa912/tasks"

    private static func taskJSON(status: String, deadline: String?, documentID: String? = documentID) -> String {
        let deadline = deadline.map { "\"\($0)\"" } ?? "null"
        let document = documentID.map { "\"\($0)\"" } ?? "null"
        let completedAt = status == "done" ? "\"2026-11-16T10:00:00Z\"" : "null"
        return """
            {"id":"2b4c6d8e-0f1a-4b3c-9d5e-7f8a9b0c1d2e","type":"pay","description":"Betaal de aanslag",
             "deadline":\(deadline),"deadline_source":"in_document","status":"\(status)",
             "completed_at":\(completedAt),"document_id":\(document),"sender":"Belastingdienst",
             "updated_at":"2026-11-16T10:00:00Z"}
            """
    }

    private func scope(_ url: URL) -> DocumentScope {
        DocumentScope(
            url: url, trust: ServerTrust(caCertificateDER: nil), token: "tok", workspaceID: Self.workspaceID
        )
    }

    @Test func openTasksDecodeDeadlineAsCalendarDate() async throws {
        let json = "[\(Self.taskJSON(status: "open", deadline: "2026-12-01")),"
            + "\(Self.taskJSON(status: "open", deadline: nil, documentID: nil))]"
        let url = try StubURLProtocol.serve(.response(status: 200, json: json))

        let tasks = try await server.openTasks(in: scope(url))

        #expect(tasks == [
            WorkspaceTask(
                id: Self.taskID, type: "pay", description: "Betaal de aanslag",
                deadline: CalendarDate(year: 2026, month: 12, day: 1), isDone: false,
                documentID: UUID(uuidString: Self.documentID), sender: "Belastingdienst"
            ),
            WorkspaceTask(
                id: Self.taskID, type: "pay", description: "Betaal de aanslag", deadline: nil, isDone: false,
                documentID: nil, sender: "Belastingdienst"
            )
        ])
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path() == Self.tasksPath)
        #expect(request.url?.query() == "status=open")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }

    @Test func completeTaskPostsAndReturnsDone() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.taskJSON(status: "done", deadline: nil)))

        let task = try await server.completeTask(Self.taskID, in: scope(url))

        #expect(task.isDone)
        #expect(task.id == Self.taskID)
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "\(Self.tasksPath)/2b4c6d8e-0f1a-4b3c-9d5e-7f8a9b0c1d2e/complete")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    }

    @Test func reopenTaskPostsAndReturnsOpen() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.taskJSON(status: "open", deadline: nil)))

        let task = try await server.reopenTask(Self.taskID, in: scope(url))

        #expect(!task.isDone)
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "\(Self.tasksPath)/2b4c6d8e-0f1a-4b3c-9d5e-7f8a9b0c1d2e/reopen")
    }

    @Test func taskNotFoundMapsToNotFound() async throws {
        let url = try StubURLProtocol.serve(.response(status: 404, json: #"{"code":"task_not_found","message":"x"}"#))
        let store = ConnectionStore(secrets: InMemorySecretStore())
        let connection = ServerConnection(urls: [url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn")
        try store.save(connection, token: "tok")
        let documents = WorkspaceDocuments(
            workspaceID: Self.workspaceID, connection: connection, store: store, server: server
        )

        await #expect(throws: DocumentsError.notFound) { try await documents.completeTask(Self.taskID) }
    }

    @Test func aTaskInADocumentReadsItsStatus() async throws {
        let json = """
            {"id":"\(Self.documentID)","client_id":"0b7f6b0e-6a5d-4c59-9d0e-0d6a3c3b9a11",
             "status":"done","page_count":1,"created_at":"2026-11-14T10:00:00Z","sender":"CAK","document_type":"bill",
             "letter_date":null,"failure_code":"","summary":"","summary_by_ai":false,"pages":[],"proposals":[],
             "tasks":[
               {"id":"2b4c6d8e-0f1a-4b3c-9d5e-7f8a9b0c1d2e","type":"pay","description":"Betaal","deadline":null,
                "deadline_source":"manual","deadline_quote":"","status":"done",
                "completed_at":"2026-11-16T10:00:00Z"},
               {"id":"3c5d7e9f-1a2b-4c3d-8e4f-5a6b7c8d9e0f","type":"pay","description":"Betaal","deadline":null,
                "deadline_source":"manual","deadline_quote":"","status":"open"}
             ]}
            """
        let url = try StubURLProtocol.serve(.response(status: 200, json: json))
        let documentID = try #require(UUID(uuidString: Self.documentID))

        let detail = try await server.document(documentID, in: scope(url))

        #expect(detail.tasks.map(\.isDone) == [true, false])
    }
}
