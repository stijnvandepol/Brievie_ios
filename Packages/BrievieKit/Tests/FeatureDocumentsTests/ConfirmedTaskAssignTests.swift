import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// Who does a task of a confirmed letter: the amount and "Bij Anne" / "Jij doet dit", "Ik doe dit" on a task
/// nobody has and "Niet meer aan mij" on one's own; never someone else's task.
@MainActor
@Suite struct ConfirmedTaskAssignTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")
    private let documentID = UUID()
    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id, status: .done) }
    private let events = EventLog()

    private func task(assignedTo: UUID? = nil, name: String = "", done: Bool = false) -> ConfirmedTask {
        ConfirmedTask(
            id: UUID(), type: "pay", description: "Betaal de aanslag", deadline: nil, deadlineSource: "manual",
            deadlineQuote: "", isDone: done, amount: TaskAmount.parse(api: "12.50"), assignedToID: assignedTo,
            assignedToName: name
        )
    }

    private func model(_ tasks: [ConfirmedTask], canEdit: Bool = true) async throws -> ConfirmedDocumentModel {
        let store = ConnectionStore(secrets: InMemorySecretStore())
        let connection = ServerConnection(urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn")
        try store.save(connection, token: "tok")
        let base = DocumentFixtures.detail(id: documentID, status: .done)
        let detail = DocumentDetail(
            summary: base.summary, failureCode: "", summaryText: "", summaryByAI: false, pageTexts: [],
            proposals: [], tasks: tasks
        )
        let model = ConfirmedDocumentModel(
            detail: detail, persons: [], labels: [],
            documents: WorkspaceDocuments(workspaceID: UUID(), connection: connection, store: store, server: server),
            canEdit: canEdit, onRevoked: {}, onMissingPairing: {}
        )
        let events = events
        model.onTasksChanged = { events.add("changed") }
        await model.loadCurrentUser()
        return model
    }

    @Test func takeOnAssignsToMeAndUpdatesTheRow() async throws {
        let free = task()
        let model = try await model([free])
        server.onAssignTask { _, id, user in
            WorkspaceTask(
                id: id, type: "pay", description: "", deadline: nil, isDone: false, documentID: nil, sender: "",
                assignedToID: user, assignedToName: "Stijn"
            )
        }
        #expect(model.canTakeOn(free))

        await model.takeOn(free.id)

        #expect(server.calls.contains(.assignTask(Self.url, free.id, FakeDocumentServer.currentUser)))
        let row = try #require(model.tasks.first)
        #expect(model.whoDoesIt(row) == "Jij doet dit")
        #expect(model.isMine(row))
        #expect(model.canRelease(row))
        #expect(!model.canTakeOn(row))
        #expect(events.all == ["changed"])
    }

    @Test func releaseSendsNoUser() async throws {
        let mine = task(assignedTo: FakeDocumentServer.currentUser, name: "Stijn")
        let model = try await model([mine])

        await model.release(mine.id)

        #expect(server.calls.contains(.assignTask(Self.url, mine.id, nil)))
    }

    @Test func someoneElsesTaskSaysWhoAndCannotBeTaken() async throws {
        let anne = task(assignedTo: UUID(), name: "Anne")
        let model = try await model([anne])

        await model.takeOn(anne.id)
        await model.release(anne.id)

        #expect(model.whoDoesIt(anne) == "Bij Anne")
        #expect(!model.canTakeOn(anne) && !model.canRelease(anne))
        #expect(!server.calls.contains { if case .assignTask = $0 { true } else { false } })
    }

    @Test func aViewerCannotTakeOn() async throws {
        let free = task()
        let model = try await model([free], canEdit: false)

        await model.takeOn(free.id)

        #expect(!model.canTakeOn(free))
        #expect(!server.calls.contains(.currentUserID(Self.url)))
        #expect(!server.calls.contains { if case .assignTask = $0 { true } else { false } })
    }

    @Test func aDoneTaskIsNotPickedUp() async throws {
        let done = task(done: true)
        let model = try await model([done])

        #expect(!model.canTakeOn(done))
    }

    @Test func anOlderServerWithoutMeShowsNoButtons() async throws {
        server.onCurrentUserID { _ in throw ServerError.other("http_404") }
        let free = task()
        let model = try await model([free])

        #expect(model.currentUserID == nil)
        #expect(!model.canTakeOn(free))
        #expect(model.changeError == nil)
    }

    @Test func aTaskSomeoneTookMeanwhileSaysSo() async throws {
        let free = task()
        let model = try await model([free])
        server.onAssignTask { _, _, _ in throw ServerError.other("task_taken") }

        await model.takeOn(free.id)

        #expect(model.changeError == DocumentStrings.myTasksTaken)
        #expect(server.calls.contains(.detail(Self.url, documentID)))
    }
}
