@testable import BrievieCore
import Foundation
import Testing

/// The "Mijn taken" calls of `LiveBrievieServer` against `StubURLProtocol`.
@Suite struct LiveBrievieServerMyTasksTests {
    private let server = LiveBrievieServer(configuration: StubURLProtocol.configuration)
    private static let workspaceID = UUID(uuidString: "71673A98-9DD7-4023-A848-FEA48B8AA912") ?? UUID()
    private static let taskID = UUID(uuidString: "2B4C6D8E-0F1A-4B3C-9D5E-7F8A9B0C1D2E") ?? UUID()
    private static let userID = UUID(uuidString: "5F1E2D3C-4B5A-4968-8776-655443322110") ?? UUID()
    private static let workspacePath = "/api/v1/workspaces/71673a98-9dd7-4023-a848-fea48b8aa912"
    private static let taskPath = "\(workspacePath)/tasks/2b4c6d8e-0f1a-4b3c-9d5e-7f8a9b0c1d2e"

    private static let taskJSON = """
        {"id":"2b4c6d8e-0f1a-4b3c-9d5e-7f8a9b0c1d2e","type":"pay","description":"Betaal de aanslag",
         "deadline":"2026-12-01","deadline_source":"manual","status":"open","completed_at":null,
         "document_id":null,"sender":"Belastingdienst","updated_at":"2026-11-16T10:00:00Z",
         "assigned_to_id":"5f1e2d3c-4b5a-4968-8776-655443322110","assigned_to_name":"Anne"}
        """

    private func scope(_ url: URL) -> DocumentScope {
        DocumentScope(
            url: url, trust: ServerTrust(caCertificateDER: nil), token: "tok", workspaceID: Self.workspaceID
        )
    }

    private func body(_ url: URL) throws -> [String: Any] {
        let request = try #require(StubURLProtocol.requests(to: url).first)
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func myTasksSendsPartAndStatusAndDecodesTheWrapper() async throws {
        let json = """
            {"items":[\(Self.taskJSON)],"today":"2026-11-21","has_person":true,"truncated":false,
             "waiting_letters":3,"split":true}
            """
        let url = try StubURLProtocol.serve(.response(status: 200, json: json))

        let answer = try await server.myTasks(part: .toPickUp, status: .open, in: scope(url))

        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.url?.path() == "\(Self.workspacePath)/my-tasks")
        #expect(request.url?.query()?.contains("part=to_pick_up") == true)
        #expect(request.url?.query()?.contains("status=open") == true)
        #expect(answer.today == CalendarDate(year: 2026, month: 11, day: 21))
        #expect(answer.waitingLetters == 3 && answer.split && answer.hasPerson && !answer.truncated)
        #expect(answer.items.map(\.assignedToName) == ["Anne"])
    }

    @Test func aTodayThatIsNoDateIsIncompatible() async throws {
        let json = #"{"items":[],"today":"morgen","has_person":true,"truncated":false,"waiting_letters":0,"#
            + #""split":false}"#
        let url = try StubURLProtocol.serve(.response(status: 200, json: json))

        await #expect(throws: ServerError.incompatible) {
            try await server.myTasks(part: .mine, status: .done, in: scope(url))
        }
    }

    @Test func countsDecode() async throws {
        let json = #"{"mine":4,"overdue":1,"within_week":2,"needs_date":1,"to_pick_up":3}"#
        let url = try StubURLProtocol.serve(.response(status: 200, json: json))

        let counts = try await server.myTaskCounts(in: scope(url))

        #expect(counts == MyTaskCounts(mine: 4, overdue: 1, withinWeek: 2, needsDate: 1, toPickUp: 3))
        #expect(StubURLProtocol.requests(to: url).first?.url?.path() == "\(Self.workspacePath)/my-tasks/counts")
    }

    @Test func assignSendsTheUser() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.taskJSON))

        let task = try await server.assignTask(Self.taskID, to: Self.userID, in: scope(url))

        #expect(task.assignedToID == Self.userID)
        let request = try #require(StubURLProtocol.requests(to: url).first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path() == "\(Self.taskPath)/assign")
        #expect(try body(url)["user_id"] as? String == "5f1e2d3c-4b5a-4968-8776-655443322110")
    }

    @Test func releaseSendsNoUser() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.taskJSON))

        _ = try await server.assignTask(Self.taskID, to: nil, in: scope(url))

        // The server's `user_id` defaults to null: left out or null both release the task.
        let value = try body(url)["user_id"]
        #expect(value == nil || value is NSNull)
    }

    @Test func assigneeCannotReadPassesThrough() async throws {
        let body = #"{"code":"assignee_cannot_read","message":"x"}"#
        let url = try StubURLProtocol.serve(.response(status: 422, json: body))

        await #expect(throws: ServerError.other("assignee_cannot_read")) {
            try await server.assignTask(Self.taskID, to: Self.userID, in: scope(url))
        }
    }

    @Test func aConflictOnAssigningIsTaskTaken() async throws {
        let body = #"{"code":"task_taken","message":"x"}"#
        let url = try StubURLProtocol.serve(.response(status: 409, json: body))

        await #expect(throws: ServerError.other("task_taken")) {
            try await server.assignTask(Self.taskID, to: Self.userID, in: scope(url))
        }
    }

    @Test func assigneesDecodeNamesOnly() async throws {
        let json = """
            [{"user_id":"5f1e2d3c-4b5a-4968-8776-655443322110","name":"Anne","is_me":false},
             {"user_id":"0e3a54c1-7b2f-4d6e-9a8b-1c2d3e4f5a6b","name":"Stijn","is_me":true}]
            """
        let url = try StubURLProtocol.serve(.response(status: 200, json: json))

        let people = try await server.taskAssignees(Self.taskID, in: scope(url))

        #expect(people.map(\.name) == ["Anne", "Stijn"])
        #expect(people.map(\.isMe) == [false, true])
        #expect(people.first?.id == Self.userID)
        #expect(StubURLProtocol.requests(to: url).first?.url?.path() == "\(Self.taskPath)/assignees")
    }

    @Test func setDeadlineSendsTheIsoDate() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.taskJSON))

        let task = try await server.setTaskDeadline(
            Self.taskID, to: CalendarDate(year: 2026, month: 12, day: 1), in: scope(url)
        )

        #expect(task.deadline == CalendarDate(year: 2026, month: 12, day: 1))
        #expect(StubURLProtocol.requests(to: url).first?.url?.path() == "\(Self.taskPath)/deadline")
        #expect(try body(url)["deadline"] as? String == "2026-12-01")
    }

    @Test func removingTheDeadlineSendsNoDate() async throws {
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.taskJSON))

        _ = try await server.setTaskDeadline(Self.taskID, to: nil, in: scope(url))

        let value = try body(url)["deadline"]
        #expect(value == nil || value is NSNull)
    }

    @Test func currentUserIDReadsOnlyTheID() async throws {
        let json = """
            {"id":"5f1e2d3c-4b5a-4968-8776-655443322110","email":"a@example.nl","name":"Anne","language":"nl",
             "explanation_language":"nl","is_server_admin":false}
            """
        let url = try StubURLProtocol.serve(.response(status: 200, json: json))

        let id = try await server.currentUserID(in: scope(url))

        #expect(id == Self.userID)
        #expect(StubURLProtocol.requests(to: url).first?.url?.path() == "/api/v1/me")
    }

    @Test func myTasksOnAnOlderServerIsNotSupported() async throws {
        let body = #"{"detail":"Not Found"}"#
        let url = try StubURLProtocol.serve(.response(status: 404, json: body))
        let store = ConnectionStore(secrets: InMemorySecretStore())
        let connection = ServerConnection(urls: [url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn")
        try store.save(connection, token: "tok")
        let documents = WorkspaceDocuments(
            workspaceID: Self.workspaceID, connection: connection, store: store, server: server
        )

        await #expect(throws: DocumentsError.notSupported) {
            try await documents.myTasks(part: .mine, status: .open)
        }
        await #expect(throws: DocumentsError.notSupported) { try await documents.myTaskCounts() }
    }
}
