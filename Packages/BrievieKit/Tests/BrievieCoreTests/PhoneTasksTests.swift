@testable import BrievieCore
import Foundation
import Testing

/// The tasks the phone's reminders and calendar follow: "Mijn taken", or all; an older server gives all open tasks.
@Suite struct PhoneTasksTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")
    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
    private let own = WorkspaceTask(
        id: UUID(), type: "pay", description: "Mijn taak", deadline: nil, isDone: false, documentID: nil, sender: ""
    )
    private let any = WorkspaceTask(
        id: UUID(), type: "pay", description: "Elke taak", deadline: nil, isDone: false, documentID: nil, sender: ""
    )

    private func documents() throws -> WorkspaceDocuments {
        let store = ConnectionStore(secrets: InMemorySecretStore())
        let connection = ServerConnection(urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn")
        try store.save(connection, token: "tok")
        let own = own
        server.onMyTasks { _, _, _ in MyTasks(items: [own], today: CalendarDate(year: 2026, month: 11, day: 21)) }
        let any = any
        server.onOpenTasks { _ in [any] }
        return WorkspaceDocuments(workspaceID: UUID(), connection: connection, store: store, server: server)
    }

    @Test func remindersReadMine() async throws {
        let tasks = try await documents().phoneTasks(.mine)

        #expect(tasks == [own])
        #expect(server.calls == [.myTasks(Self.url, .mine, .open)])
    }

    @Test func allAsksForAll() async throws {
        _ = try await documents().phoneTasks(.all)

        #expect(server.calls == [.myTasks(Self.url, .all, .open)])
    }

    @Test func phoneTasksFallBackToListTasksOn404() async throws {
        let documents = try documents()
        server.onMyTasks { _, _, _ in throw ServerError.other("http_404") }

        let tasks = try await documents.phoneTasks(.mine)

        #expect(tasks == [any])
        #expect(server.calls == [.myTasks(Self.url, .mine, .open), .openTasks(Self.url)])
    }

    @Test func aRealErrorIsNotAFallback() async throws {
        let documents = try documents()
        server.onMyTasks { _, _, _ in throw ServerError.unreachable }

        await #expect(throws: DocumentsError.unreachable) { try await documents.phoneTasks(.mine) }
        #expect(!server.calls.contains(.openTasks(Self.url)))
    }

    @Test func toPickUpIsNeverReminded() async throws {
        _ = try await documents().phoneTasks(.toPickUp)

        #expect(server.calls == [.myTasks(Self.url, .mine, .open)])
    }
}
