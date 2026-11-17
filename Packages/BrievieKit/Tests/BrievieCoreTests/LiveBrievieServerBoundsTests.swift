@testable import BrievieCore
import Foundation
import Testing

/// A JSON answer is read into memory before it is decoded: a broken or hostile server must not be able to
/// send an unbounded body.
@Suite struct LiveBrievieServerBoundsTests {
    private static let workspaceID = UUID(uuidString: "71673A98-9DD7-4023-A848-FEA48B8AA912") ?? UUID()

    private func scope(_ url: URL) -> DocumentScope {
        DocumentScope(url: url, trust: ServerTrust(caCertificateDER: nil), token: "tok", workspaceID: Self.workspaceID)
    }

    private static func tasksJSON(count: Int) -> String {
        let task = """
            {"id":"2b4c6d8e-0f1a-4b3c-9d5e-7f8a9b0c1d2e","type":"pay","description":"Betaal de aanslag",
             "deadline":null,"deadline_source":"in_document","status":"open","completed_at":null,
             "document_id":null,"sender":"Belastingdienst","updated_at":"2026-11-16T10:00:00Z"}
            """
        return "[" + Array(repeating: task, count: count).joined(separator: ",") + "]"
    }

    @Test func aJSONAnswerAboveTheCapIsRefused() async throws {
        let server = LiveBrievieServer(configuration: StubURLProtocol.configuration, maxJSONBytes: 2_048)
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.tasksJSON(count: 20)))

        await #expect(throws: ServerError.responseTooLarge) {
            try await server.openTasks(in: scope(url))
        }
    }

    @Test func aJSONAnswerUnderTheCapIsRead() async throws {
        let server = LiveBrievieServer(configuration: StubURLProtocol.configuration, maxJSONBytes: 2_048)
        let url = try StubURLProtocol.serve(.response(status: 200, json: Self.tasksJSON(count: 1)))

        let tasks = try await server.openTasks(in: scope(url))

        #expect(tasks.count == 1)
    }

    @Test func anErrorBodyAboveTheCapIsRefusedToo() async throws {
        let server = LiveBrievieServer(configuration: StubURLProtocol.configuration, maxJSONBytes: 64)
        let body = #"{"code":"workspace_not_found","message":""# + String(repeating: "x", count: 200) + #""}"#
        let url = try StubURLProtocol.serve(.response(status: 404, json: body))

        await #expect(throws: ServerError.responseTooLarge) {
            try await server.openTasks(in: scope(url))
        }
    }

    @Test func theDefaultCapIsANamedConstantOfSomeMegabytes() {
        // The largest real answer is a letter of 30 pages of 20000 characters: well under 8 MiB as JSON.
        #expect(LiveBrievieServer.maxJSONResponseBytes >= 8 * 1024 * 1024)
        #expect(LiveBrievieServer.maxJSONResponseBytes <= 32 * 1024 * 1024)
    }
}
