import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// "Mijn taken" next to the Inbox: its counts, the link row, the screen of the "Taken" tab, and an older server
/// without it.
@MainActor
@Suite struct DocumentsMyTasksTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")

    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
    private let events = EventLog()

    private func model() throws -> DocumentsModel {
        let store = ConnectionStore(secrets: InMemorySecretStore())
        let connection = ServerConnection(urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn")
        try store.save(connection, token: "tok")
        let model = DocumentsModel(
            documents: WorkspaceDocuments(workspaceID: UUID(), connection: connection, store: store, server: server),
            uploads: FakeUploadQueue(), canScan: true, camera: FakeScanCamera(.allowed), openSettings: {},
            onRevoked: {}, onMissingPairing: {}
        )
        let events = events
        model.onTasksChanged = { events.add("changed") }
        return model
    }

    private var countCalls: Int {
        server.calls.filter { $0 == .myTaskCounts(Self.url) }.count
    }

    @Test func loadReadsTheCountsWithTheInbox() async throws {
        server.onMyTaskCounts { _ in MyTaskCounts(mine: 4, overdue: 1) }
        let model = try model()

        await model.load()

        #expect(countCalls == 1)
        #expect(model.hasMyTasks)
        #expect(model.myTaskCounts == MyTaskCounts(mine: 4, overdue: 1))
    }

    @Test func theLinkSaysOnlyOpenWithoutLateTasks() async throws {
        server.onMyTaskCounts { _ in MyTaskCounts(mine: 3) }
        let model = try model()

        await model.load()

        #expect(model.myTasksLink == DocumentsModel.MyTasksLink(text: "Mijn taken: 3 open", isLate: false))
    }

    @Test func inboxLinkSaysLateInWords() async throws {
        server.onMyTaskCounts { _ in MyTaskCounts(mine: 4, overdue: 1) }
        let model = try model()
        await model.load()

        #expect(model.myTasksLink
            == DocumentsModel.MyTasksLink(text: "Mijn taken: 4 open, waarvan 1 te laat", isLate: true))

        await model.select(.all)
        #expect(model.myTasksLink == nil)
    }

    @Test func noOpenTasksNoLink() async throws {
        server.onMyTaskCounts { _ in MyTaskCounts(mine: 0) }
        let model = try model()

        await model.load()

        #expect(model.myTasksLink == nil)
    }

    @Test func anOlderServerHasNoMyTasks() async throws {
        server.onMyTaskCounts { _ in throw ServerError.other("http_404") }
        let model = try model()

        await model.load()

        #expect(!model.hasMyTasks)
        #expect(model.myTasksLink == nil)
        #expect(model.state == .loaded)
    }

    @Test func anUnreachableCountKeepsWhatWasKnown() async throws {
        server.onMyTaskCounts { _ in MyTaskCounts(mine: 2) }
        let model = try model()
        await model.load()
        server.onMyTaskCounts { _ in throw ServerError.unreachable }

        await model.load()

        #expect(model.hasMyTasks)
        #expect(model.myTaskCounts == MyTaskCounts(mine: 2))
    }

    @Test func naarInboxGoesToTheInboxTab() async throws {
        let model = try model()
        await model.load()
        let events = events
        let tasks = model.makeMyTasksModel { events.add("inbox") }

        tasks.showInbox()

        #expect(events.all == ["inbox"])
    }

    @Test func aModelStartsOnTheScopeItIsMadeFor() throws {
        #expect(try model().scope == .inbox)
        let store = ConnectionStore(secrets: InMemorySecretStore())
        let connection = ServerConnection(urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Jij")
        let myPost = DocumentsModel(
            documents: WorkspaceDocuments(workspaceID: UUID(), connection: connection, store: store, server: server),
            scope: .myPost, uploads: FakeUploadQueue(), canScan: true, camera: FakeScanCamera(.allowed),
            openSettings: {}, onRevoked: {}, onMissingPairing: {}
        )
        #expect(myPost.scope == .myPost)
        #expect(myPost.scopeTitle == "Mijn post")
        #expect(!myPost.searchIsAvailable)
    }

    @Test func aTickInMyTasksRefreshesTheCounts() async throws {
        let task = MyTasksHarness.task()
        server.onMyTasks { _, _, _ in MyTasks(items: [task], today: MyTasksHarness.today) }
        server.onMyTaskCounts { _ in MyTaskCounts(mine: 1) }
        let model = try model()
        await model.load()
        let tasks = model.makeMyTasksModel {}
        await tasks.load()

        await tasks.setDone(true, for: task.id)
        while countCalls < 2 { await Task.yield() }

        #expect(events.all == ["changed"])
        #expect(server.calls.contains(.completeTask(Self.url, task.id)))
    }
}
