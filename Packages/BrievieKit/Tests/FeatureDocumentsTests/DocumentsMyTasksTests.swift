import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// "Mijn taken" next to the Inbox: the menu entry with its count, the link row, switching back and forth, and an
/// older server without it.
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
        #expect(model.myTasksMenuTitle == "Mijn taken · 4 open, 1 te laat")
    }

    @Test func theMenuSaysOnlyOpenWithoutLateTasks() async throws {
        server.onMyTaskCounts { _ in MyTaskCounts(mine: 3) }
        let model = try model()

        await model.load()

        #expect(model.myTasksMenuTitle == "Mijn taken · 3 open")
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
        #expect(model.myTasksMenuTitle == "Mijn taken")
    }

    @Test func menuHidesMyTasksOnAnOlderServer() async throws {
        server.onMyTaskCounts { _ in throw ServerError.other("http_404") }
        let model = try model()

        await model.load()

        #expect(!model.hasMyTasks)
        #expect(model.myTasksLink == nil)
        #expect(model.state == .loaded)
        model.showMyTasks()
        #expect(!model.isShowingMyTasks)
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

    @Test func pickingAScopeLeavesMyTasks() async throws {
        let model = try model()
        await model.load()
        model.showMyTasks()
        #expect(model.isShowingMyTasks)
        #expect(model.screenTitle == "Mijn taken")
        #expect(!model.searchIsAvailable)

        await model.select(.all)

        #expect(!model.isShowingMyTasks)
        #expect(model.searchIsAvailable)
    }

    @Test func pickingTheCurrentScopeAlsoLeavesMyTasks() async throws {
        let model = try model()
        await model.load()
        model.showMyTasks()

        await model.select(.inbox)

        #expect(!model.isShowingMyTasks)
    }

    @Test func myTasksShowInboxGoesBackToTheInbox() async throws {
        let model = try model()
        await model.load()
        await model.select(.all)
        model.showMyTasks()
        let tasks = model.makeMyTasksModel()

        tasks.showInbox()
        while model.isShowingMyTasks { await Task.yield() }
        while model.scope != .inbox { await Task.yield() }

        #expect(model.scope == .inbox)
    }

    @Test func theStartScreenIsStillTheInbox() throws {
        let model = try model()

        #expect(!model.isShowingMyTasks)
        #expect(model.scope == .inbox)
    }

    @Test func aTickInMyTasksRefreshesTheCounts() async throws {
        let task = MyTasksHarness.task()
        server.onMyTasks { _, _, _ in MyTasks(items: [task], today: MyTasksHarness.today) }
        server.onMyTaskCounts { _ in MyTaskCounts(mine: 1) }
        let model = try model()
        await model.load()
        let tasks = model.makeMyTasksModel()
        await tasks.load()

        await tasks.setDone(true, for: task.id)
        while countCalls < 2 { await Task.yield() }

        #expect(events.all == ["changed"])
        #expect(server.calls.contains(.completeTask(Self.url, task.id)))
    }
}
