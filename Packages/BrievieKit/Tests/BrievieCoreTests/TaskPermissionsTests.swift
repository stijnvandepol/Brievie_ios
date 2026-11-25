@testable import BrievieCore
import Foundation
import Testing

/// `can_take`, `can_hand_over`, `can_release` (host PR #44) on a task: read when sent, `nil` from an older server.
@Suite struct TaskPermissionsTests {
    private let server = LiveBrievieServer(configuration: StubURLProtocol.configuration)
    private static let workspaceID = UUID(uuidString: "71673A98-9DD7-4023-A848-FEA48B8AA912") ?? UUID()

    private static func taskJSON(_ extra: String) -> String {
        """
        {"id":"2b4c6d8e-0f1a-4b3c-9d5e-7f8a9b0c1d2e","type":"pay","description":"Betaal de aanslag",
         "deadline":null,"deadline_source":"manual","status":"open","completed_at":null,
         "document_id":null,"sender":"Belastingdienst","updated_at":"2026-11-16T10:00:00Z"\(extra)}
        """
    }

    private func tasks(_ extra: String) async throws -> [WorkspaceTask] {
        let json = """
            {"items":[\(Self.taskJSON(extra))],"today":"2026-11-21","has_person":true,"truncated":false,
             "waiting_letters":0,"split":false}
            """
        let url = try StubURLProtocol.serve(.response(status: 200, json: json))
        let scope = DocumentScope(
            url: url, trust: ServerTrust(caCertificateDER: nil), token: "tok", workspaceID: Self.workspaceID
        )
        return try await server.myTasks(part: .mine, status: .open, in: scope).items
    }

    @Test func theServersFlagsAreRead() async throws {
        let items = try await tasks(#","can_take":false,"can_hand_over":true,"can_release":true"#)

        #expect(items.first?.permissions == TaskPermissions(canTake: false, canHandOver: true, canRelease: true))
    }

    @Test func anOlderServerSaysNothing() async throws {
        let items = try await tasks("")

        #expect(items.first?.permissions == nil)
    }
}
