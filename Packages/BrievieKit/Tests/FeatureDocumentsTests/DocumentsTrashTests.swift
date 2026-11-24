import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// The post list and the trash: the probe for a server with a trash, the undo notice after deleting, and an
/// upload of a letter that is in the trash.
@MainActor
@Suite struct DocumentsTrashTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")

    private let workspaceID = UUID()
    private let store = ConnectionStore(secrets: InMemorySecretStore())
    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
    private let queue = FakeUploadQueue()
    private let events = EventLog()

    private func model(canScan: Bool = true) throws -> DocumentsModel {
        let connection = ServerConnection(
            urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn"
        )
        try store.save(connection, token: "tok")
        return DocumentsModel(
            documents: WorkspaceDocuments(
                workspaceID: workspaceID, connection: connection, store: store, server: server
            ),
            uploads: queue, canScan: canScan, camera: FakeScanCamera(.allowed), openSettings: {},
            onRevoked: { [events] in events.add("revoked") },
            onMissingPairing: { [events] in events.add("missing") }
        )
    }

    private var trashListCalls: Int {
        server.calls.count { if case .trashList = $0 { true } else { false } }
    }

    @Test func aServerWithoutATrashHidesItAndIsNotAskedOnEveryTick() async throws {
        server.onTrashList { _ in throw ServerError.other("http_404") }
        // Something on its way, so the tick really asks the server.
        queue.set([FakeUploadQueue.item(workspaceID: workspaceID)])
        let model = try model()

        await model.load()
        #expect(!model.hasTrash)
        #expect(trashListCalls == 1)

        await model.refreshIfNeeded()

        #expect(trashListCalls == 1)
        #expect(!model.hasTrash)
    }

    @Test func aServerWithATrashShowsIt() async throws {
        let model = try model()
        #expect(!model.hasTrash)

        await model.load()

        #expect(model.hasTrash)
    }

    @Test func aFailingProbeKeepsWhatWasKnown() async throws {
        let model = try model()
        await model.load()
        #expect(model.hasTrash)

        server.onTrashList { _ in throw ServerError.unreachable }
        await model.load()

        #expect(model.hasTrash)
    }

    @Test func afterDeletingTheListOffersUndo() async throws {
        let id = UUID()
        let model = try model()
        await model.load()
        let listsBefore = server.calls.count { if case .list = $0 { true } else { false } }

        await model.didTrash(id)

        #expect(model.undo?.documentID == id)
        #expect(model.undo?.message == "De brief staat in de prullenbak.")
        #expect(model.undo?.failure == nil)
        #expect(server.calls.count { if case .list = $0 { true } else { false } } > listsBefore)
    }

    @Test func undoRestoresAndOpensTheLetterAgain() async throws {
        let id = UUID()
        let model = try model()
        await model.load()
        await model.didTrash(id)

        await model.undoTrash()

        #expect(server.calls.contains(.restore(Self.url, id)))
        #expect(model.undo == nil)
        #expect(model.openedDocument == id)
    }

    /// "Ongedaan maken" in Taken: the letter comes back, but does not open on this list's tab, out of sight.
    @Test func undoFromAnotherTabRestoresWithoutOpening() async throws {
        let id = UUID()
        let model = try model()
        await model.load()
        await model.didTrash(id)

        await model.undoTrash(reopen: false)

        #expect(server.calls.contains(.restore(Self.url, id)))
        #expect(model.undo == nil)
        #expect(model.openedDocument == nil)
    }

    @Test func aFailedUndoKeepsTheNoticeWithTheReason() async throws {
        let id = UUID()
        server.onRestore { _, _ in throw ServerError.other("document_not_found") }
        let model = try model()
        await model.load()
        await model.didTrash(id)

        await model.undoTrash()

        #expect(model.undo?.documentID == id)
        #expect(model.undo?.failure == "De brief kan niet meer worden teruggezet.")
        #expect(model.openedDocument == nil)
    }

    @Test func anUndoAfterRevocationEndsTheSession() async throws {
        server.onRestore { _, _ in throw ServerError.unauthorized }
        let model = try model()
        await model.load()
        await model.didTrash(UUID())

        await model.undoTrash()

        #expect(events.all.contains("revoked"))
        #expect(model.openedDocument == nil)
    }

    @Test func anotherScopeClearsTheUndo() async throws {
        let model = try model()
        await model.load()
        await model.didTrash(UUID())

        await model.select(.all)

        #expect(model.undo == nil)
    }

    @Test func closingTheUndoSendsNothing() async throws {
        let model = try model()
        await model.load()
        await model.didTrash(UUID())

        model.closeUndo()

        #expect(model.undo == nil)
        #expect(!server.calls.contains { if case .restore = $0 { true } else { false } })
    }

    @Test func theTrashScreenRestoresWithTheMembersRight() async throws {
        let id = UUID()
        server.onTrashList { _ in TrashList(items: [DocumentFixtures.trashed(id: id)]) }
        let viewer = try model(canScan: false)
        let trash = viewer.makeTrashModel()
        await trash.load()
        #expect(!trash.canRestore)

        let member = try model(canScan: true)
        let memberTrash = member.makeTrashModel()
        await memberTrash.load()
        await memberTrash.restore(id)
        #expect(server.calls.contains(.restore(Self.url, id)))
    }

    // MARK: - The calendar and the reminders follow (the server hides a trashed letter's tasks)

    private func countingTasksChanged(_ model: DocumentsModel) {
        model.onTasksChanged = { [events] in events.add("tasksChanged") }
    }

    private var tasksChangedCount: Int {
        events.all.count { $0 == "tasksChanged" }
    }

    @Test func deletingUpdatesTheCalendarAndReminders() async throws {
        let model = try model()
        countingTasksChanged(model)
        await model.load()

        await model.didTrash(UUID())

        #expect(tasksChangedCount == 1)
    }

    @Test func undoUpdatesTheCalendarAndRemindersAgain() async throws {
        let model = try model()
        countingTasksChanged(model)
        await model.load()
        await model.didTrash(UUID())

        await model.undoTrash()

        #expect(tasksChangedCount == 2)
    }

    @Test func aFailedUndoLeavesTheCalendarAlone() async throws {
        server.onRestore { _, _ in throw ServerError.other("document_not_found") }
        let model = try model()
        countingTasksChanged(model)
        await model.load()
        await model.didTrash(UUID())

        await model.undoTrash()

        #expect(tasksChangedCount == 1)
    }

    @Test func aRestoreOnTheTrashScreenUpdatesTheCalendarAndReminders() async throws {
        let id = UUID()
        server.onTrashList { _ in TrashList(items: [DocumentFixtures.trashed(id: id)]) }
        let model = try model()
        countingTasksChanged(model)
        let trash = model.makeTrashModel()
        await trash.load()

        await trash.restore(id)

        #expect(tasksChangedCount == 1)
    }

    // MARK: - Minor fixes

    @Test func aRestoreOnTheTrashScreenClearsTheUndoOfThatLetter() async throws {
        let id = UUID()
        server.onTrashList { _ in TrashList(items: [DocumentFixtures.trashed(id: id)]) }
        let model = try model()
        await model.load()
        await model.didTrash(id)
        let trash = model.makeTrashModel()
        await trash.load()

        await trash.restore(id)

        #expect(model.undo == nil)
    }

    @Test func aRestoreOfAnotherLetterKeepsTheUndo() async throws {
        let other = UUID()
        server.onTrashList { _ in TrashList(items: [DocumentFixtures.trashed(id: other)]) }
        let model = try model()
        await model.load()
        let id = UUID()
        await model.didTrash(id)
        let trash = model.makeTrashModel()
        await trash.load()

        await trash.restore(other)

        #expect(model.undo?.documentID == id)
    }

    @Test func anUndoDoesNotOpenTheLetterOverTheTrashScreen() async throws {
        let id = UUID()
        let model = try model()
        await model.load()
        await model.didTrash(id)
        model.isShowingTrash = true

        await model.undoTrash()

        #expect(server.calls.contains(.restore(Self.url, id)))
        #expect(model.openedDocument == nil)
    }

    @Test func anUndoDoesNotReplaceAnotherOpenedLetter() async throws {
        let id = UUID()
        let other = UUID()
        let model = try model()
        await model.load()
        await model.didTrash(id)
        model.openedDocument = other

        await model.undoTrash()

        #expect(model.openedDocument == other)
    }

    @Test func aKnownTrashIsNotAskedForAgain() async throws {
        let model = try model()
        await model.load()
        #expect(model.hasTrash)
        #expect(trashListCalls == 1)

        await model.load()
        await model.didTrash(UUID())

        #expect(trashListCalls == 1)
        #expect(model.hasTrash)
    }

    @Test func deletingRunsAnOpenSearchAgain() async throws {
        let model = try model()
        await model.select(.all)
        model.search.query = "aanslag"
        await model.search.settle()
        let searchesBefore = server.calls.count { if case .search = $0 { true } else { false } }
        #expect(searchesBefore == 1)

        await model.didTrash(UUID())
        await model.search.settle()

        #expect(server.calls.count { if case .search = $0 { true } else { false } } == 2)
    }

    @Test func anUploadOfATrashedLetterCannotBeRetried() async throws {
        queue.set([FakeUploadQueue.item(workspaceID: workspaceID, state: .failed, failureCode: "document_trashed")])
        let model = try model()

        await model.load()

        let message = "Deze brief staat al in de prullenbak. Zet hem daar terug als je hem weer wilt zien."
        #expect(model.rows.map(\.status) == [.uploadFailed(message: message, canRetry: false)])
    }
}
