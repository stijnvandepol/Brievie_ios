import BrievieCore
@testable import FeatureDocuments
import Foundation

/// A `MyTasksModel` against a `FakeDocumentServer`, with what it reported to the app.
@MainActor
struct MyTasksHarness {
    nonisolated static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")
    nonisolated static let dutch = Locale(identifier: "nl_NL")
    nonisolated static let today = CalendarDate(year: 2026, month: 11, day: 21)

    let server: FakeDocumentServer
    let events = EventLog()
    let model: MyTasksModel

    init(canEdit: Bool = true, server: FakeDocumentServer? = nil, gated: (any DocumentServer)? = nil) throws {
        let server = server ?? FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
        self.server = server
        let store = ConnectionStore(secrets: InMemorySecretStore())
        let connection = ServerConnection(urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn")
        try store.save(connection, token: "tok")
        let documents = WorkspaceDocuments(
            workspaceID: UUID(), connection: connection, store: store, server: gated ?? server
        )
        let events = events
        model = MyTasksModel(
            documents: documents, canEdit: canEdit, locale: Self.dutch,
            onTasksChanged: { events.add("changed") },
            onShowInbox: { events.add("inbox") },
            onRevoked: { events.add("revoked") },
            onMissingPairing: { events.add("missing") }
        )
    }

    /// Serves `mine` for the own and all lists, `pickUp` for "Op te pakken", `done` for Afgerond.
    func serve(
        _ mine: [WorkspaceTask], pickUp: [WorkspaceTask] = [], done: [WorkspaceTask] = [], split: Bool = false,
        hasPerson: Bool = true, truncated: Bool = false, waiting: Int = 0
    ) {
        server.onMyTasks { _, part, status in
            let items = status == .done ? done : part == .toPickUp ? pickUp : mine
            return MyTasks(
                items: items, today: Self.today, hasPerson: hasPerson, truncated: truncated,
                waitingLetters: waiting, split: split
            )
        }
    }

    var myTasksCalls: [FakeDocumentServer.Call] {
        server.calls.filter { if case .myTasks = $0 { true } else { false } }
    }

    nonisolated static func task(
        _ description: String = "Betaal de aanslag", id: UUID = UUID(), group: TaskGroup = .later,
        deadline: CalendarDate? = CalendarDate(year: 2026, month: 12, day: 1), daysLeft: Int? = 10,
        reason: TaskReason = .addressee, assignedTo: UUID? = nil, assignedToName: String = "",
        documentID: UUID? = UUID(), canEdit: Bool? = true, done: Bool = false, completedBy: String = "",
        completedAt: Date? = nil, permissions: TaskPermissions? = nil
    ) -> WorkspaceTask {
        WorkspaceTask(
            id: id, type: "pay", description: description, deadline: deadline, isDone: done, documentID: documentID,
            sender: "Belastingdienst", daysLeft: daysLeft, group: group, reason: reason, assignedToID: assignedTo,
            assignedToName: assignedToName, completedByName: completedBy, completedAt: completedAt, canEdit: canEdit,
            permissions: permissions
        )
    }
}
