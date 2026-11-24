import BrievieCore
@testable import FeatureDocuments
import Foundation
import SwiftUI
import Testing

/// The tabs of a workspace: the web's order, the start on "Mijn post", and what an older server leaves out.
@MainActor
@Suite struct WorkspaceTabsModelTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")

    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }

    private func model() throws -> WorkspaceTabsModel {
        let store = ConnectionStore(secrets: InMemorySecretStore())
        let connection = ServerConnection(urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Jij")
        try store.save(connection, token: "tok")
        return WorkspaceTabsModel(
            documents: WorkspaceDocuments(workspaceID: UUID(), connection: connection, store: store, server: server),
            onRevoked: {}, onMissingPairing: {}
        )
    }

    @Test func theTabsFollowTheWebsOrderAndStartOnMyPost() throws {
        let tabs = try model()

        #expect(tabs.tabs == [.inbox, .myPost, .tasks, .more])
        #expect(tabs.selection == .myPost)
        #expect(tabs.startTab == .myPost)
        #expect(tabs.myPostSupport == .unknown)
    }

    @Test func theSidebarFollowsTheWebsMenu() async throws {
        let tabs = try model()
        tabs.hasTrash = true

        await tabs.refreshCounts()

        #expect(tabs.sidebarItems == [.inbox, .myPost, .tasks, .allPost, .labels, .trash])
        #expect(tabs.sidebarSelection == .myPost)
    }

    @Test func theCountsGiveTheBadges() async throws {
        server.onMenuCounts { _ in MenuCounts(inbox: 3, myPostUnread: 4, myTasks: 0, myTasksOverdue: 0) }
        let tabs = try model()

        await tabs.refreshCounts()

        #expect(tabs.myPostSupport == .supported)
        #expect(tabs.badge(for: .inbox) == 3)
        #expect(tabs.badge(for: .myPost) == 4)
        #expect(tabs.badge(for: .tasks) == nil)
        #expect(tabs.badge(for: .more) == nil)
    }

    @Test func anOlderServerHasNoMyPostAndStartsOnTheInbox() async throws {
        server.onMenuCounts { _ in throw ServerError.other("http_404") }
        let tabs = try model()

        await tabs.refreshCounts()

        #expect(tabs.myPostSupport == .notSupported)
        #expect(tabs.tabs == [.inbox, .tasks, .more])
        #expect(tabs.selection == .inbox)
        #expect(tabs.startTab == .inbox)
        #expect(tabs.badge(for: .inbox) == nil)
        // "Mijn post" never asked a list it cannot trust.
        #expect(!server.calls.contains { if case .list = $0 { true } else { false } })
    }

    @Test func aServerWithoutMyTasksHasNoTasksTab() async throws {
        server.onMenuCounts { _ in throw ServerError.other("http_404") }
        server.onMyTaskCounts { _ in throw ServerError.other("http_404") }
        let tabs = try model()

        await tabs.refreshCounts()

        #expect(tabs.tabs == [.inbox, .more])
        #expect(tabs.sidebarItems == [.inbox, .allPost, .labels])
    }

    @Test func anUnreachableServerKeepsMyPostWaitingWithAReason() async throws {
        server.onMenuCounts { _ in throw ServerError.unreachable }
        let tabs = try model()

        await tabs.refreshCounts()

        #expect(tabs.myPostSupport == .unknown)
        #expect(tabs.countFailure == DocumentStrings.unreachable)
        #expect(tabs.tabs.contains(.myPost))

        server.onMenuCounts { _ in MenuCounts() }
        await tabs.refreshCounts()

        #expect(tabs.myPostSupport == .supported)
        #expect(tabs.countFailure == nil)
    }

    @Test func goingElsewhereAndBackToTheStart() throws {
        let tabs = try model()

        tabs.showAllPost()
        #expect(tabs.selection == .more && tabs.sidebarSelection == .allPost)
        #expect(tabs.morePath == NavigationPath([WorkspaceTabsModel.Place.allPost]))

        tabs.showTasks()
        #expect(tabs.selection == .tasks)

        tabs.showInbox()
        #expect(tabs.selection == .inbox && tabs.sidebarSelection == .inbox)

        tabs.showAllPost()
        tabs.showStart()
        #expect(tabs.selection == .myPost && tabs.morePath.isEmpty && tabs.sidebarSelection == .myPost)
    }

    /// A search hit in "Alle post" pushes a `SearchHitLink` onto the stack of "Meer" (and of the iPad's detail): a
    /// path of places only would refuse it, and the hit would not open.
    @Test func aSearchHitCanBePushedWhereAllePostIs() throws {
        let tabs = try model()
        tabs.showAllPost()

        tabs.morePath.append(SearchHitLink(documentID: UUID()))
        tabs.detailPath.append(SearchHitLink(documentID: UUID()))

        #expect(tabs.morePath.count == 2)
        #expect(tabs.detailPath.count == 1)
    }

    @Test func aNewWorkspaceStartsAnew() async throws {
        let first = try model()
        first.showInbox()

        // A workspace switch makes new models: the new one is back on "Mijn post".
        let second = try model()

        #expect(second.selection == .myPost)
    }
}

/// The count cards of "Mijn post".
@MainActor
@Suite struct WorkspaceTabsCardsTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")

    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }

    private func loaded(_ counts: MenuCounts) async throws -> WorkspaceTabsModel {
        server.onMenuCounts { _ in counts }
        let store = ConnectionStore(secrets: InMemorySecretStore())
        let connection = ServerConnection(urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Jij")
        try store.save(connection, token: "tok")
        let tabs = WorkspaceTabsModel(
            documents: WorkspaceDocuments(workspaceID: UUID(), connection: connection, store: store, server: server),
            onRevoked: {}, onMissingPairing: {}
        )
        await tabs.refreshCounts()
        return tabs
    }

    @Test func unreadAndTasksSayThemselvesInWords() async throws {
        let tabs = try await loaded(MenuCounts(myPostUnread: 4, myTasks: 2, myTasksOverdue: 1))

        #expect(tabs.cards.map(\.kind) == [.unread, .tasks])
        #expect(tabs.cards.map(\.number) == [4, 2])
        #expect(tabs.cards.map(\.accessibilityLabel) == ["Mijn post: 4 ongelezen", "Mijn taken: 2 open, 1 te laat"])
        #expect(tabs.cards.last?.detail == "1 te laat")
        #expect(tabs.cards.last?.detailIsWarning == true)
    }

    @Test func lingeringOnlyForWhoSortsInAnOrganisation() async throws {
        let home = try await loaded(MenuCounts(lingering: 0, showsLingering: false))
        let office = try await loaded(MenuCounts(lingering: 3, showsLingering: true))

        #expect(!home.cards.contains { $0.kind == .lingering })
        #expect(office.cards.last?.kind == .lingering)
        #expect(office.cards.last?.accessibilityLabel == "Blijft liggen: 3")
    }

    @Test func withoutAPersonMyPostSaysWhy() async throws {
        let tabs = try await loaded(MenuCounts(hasPerson: false))

        #expect(tabs.lacksPerson)
    }

    @Test func theListsHearOnceWhetherTheServerKeepsReadMarks() async throws {
        server.onMenuCounts { _ in MenuCounts() }
        let store = ConnectionStore(secrets: InMemorySecretStore())
        let connection = ServerConnection(urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Jij")
        try store.save(connection, token: "tok")
        let tabs = WorkspaceTabsModel(
            documents: WorkspaceDocuments(workspaceID: UUID(), connection: connection, store: store, server: server),
            onRevoked: {}, onMissingPairing: {}
        )
        let events = EventLog()
        tabs.onReadingSupport = { events.add("\($0)") }
        var searched = false
        tabs.onSearch = { searched = true }

        await tabs.refreshCounts()
        await tabs.refreshCounts()
        tabs.showSearch()

        #expect(events.all == ["true"])
        #expect(searched)
        #expect(tabs.selection == .more && tabs.morePath == NavigationPath([WorkspaceTabsModel.Place.allPost]))
    }
}
