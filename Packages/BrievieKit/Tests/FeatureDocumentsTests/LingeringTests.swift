import BrievieCore
@testable import FeatureDocuments
import Foundation
import SwiftUI
import Testing

/// "Blijft liggen" and the Inbox's round actions, and how a workspace's screens are tied together.
@MainActor
@Suite struct LingeringTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")

    private let store = ConnectionStore(secrets: InMemorySecretStore())
    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }

    private func documents() throws -> WorkspaceDocuments {
        let connection = ServerConnection(urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Jij")
        try store.save(connection, token: "tok")
        return WorkspaceDocuments(workspaceID: UUID(), connection: connection, store: store, server: server)
    }

    private func screens() throws -> WorkspaceScreens {
        WorkspaceScreens(
            documents: try documents(), uploads: FakeUploadQueue(), canScan: true, camera: FakeScanCamera(.allowed),
            openSettings: {}, onTasksChanged: {}, onRevoked: {}, onMissingPairing: {}
        )
    }

    private nonisolated static func letter(_ state: InboxState, addressees: [UUID] = []) -> DocumentSummary {
        DocumentSummary(
            id: UUID(), clientID: UUID(), status: .done, pageCount: 1, createdAt: Date(timeIntervalSince1970: 1),
            sender: "Gemeente", documentType: "", letterDate: nil, inboxState: state, addresseeIDs: addressees
        )
    }

    @Test func theTwoGroupsSayHowLongEachLetterLies() async throws {
        let person = DocumentFixtures.persons[0]
        let waiting = Self.letter(.review)
        let unopened = Self.letter(.sorted, addressees: [person.id])
        server.onLingering { _ in
            LingeringLetters(
                tooLongInInbox: [LingeringLetter(document: waiting, days: 4)],
                notOpened: [LingeringLetter(document: unopened, days: 1)], inboxDays: 2, unopenedDays: 5
            )
        }
        let model = LingeringModel(
            documents: try documents(), persons: { [person] }, labels: { [] }, onRevoked: {}, onMissingPairing: {}
        )

        await model.load()

        #expect(model.state == .loaded)
        #expect(model.groups.map(\.title) == ["In de Inbox te lang", "Nog niet geopend"])
        #expect(model.groups.map { $0.rows.map(\.age) } == [["Ligt er 4 dagen"], ["1 dag niet geopend"]])
        #expect(model.groups.last?.rows.first?.row.addressees == [person.displayName])
        #expect(model.groups.first?.rows.first?.accessibilityLabel.hasSuffix(", Ligt er 4 dagen") == true)
    }

    @Test func anEmptyGroupIsLeftOut() async throws {
        server.onLingering { _ in
            LingeringLetters(
                tooLongInInbox: [], notOpened: [LingeringLetter(document: Self.letter(.sorted), days: 6)],
                inboxDays: 2, unopenedDays: 5
            )
        }
        let model = LingeringModel(
            documents: try documents(), persons: { [] }, labels: { [] }, onRevoked: {}, onMissingPairing: {}
        )

        await model.load()

        #expect(model.groups.map(\.kind) == [.notOpened])
        #expect(!model.isEmpty)
    }

    @Test func aFailureSaysWhy() async throws {
        server.onLingering { _ in throw ServerError.unreachable }
        let model = LingeringModel(
            documents: try documents(), persons: { [] }, labels: { [] }, onRevoked: {}, onMissingPairing: {}
        )

        await model.load()

        #expect(model.state == .failed(message: DocumentStrings.unreachable))
    }

    @Test func theLingeringCardOpensItOnTheInbox() throws {
        let screens = try screens()
        screens.tabs.selection = .inbox

        screens.tabs.showLingering(from: .inbox)

        #expect(screens.tabs.selection == .inbox)
        #expect(screens.tabs.lingeringShownIn == .inbox)
    }

    /// Tapping the card in "Mijn post" opens the list there: the tab bar does not jump to the Inbox.
    @Test func theLingeringCardInMyPostStaysInMyPost() throws {
        let screens = try screens()
        screens.tabs.selection = .myPost
        screens.tabs.sidebarSelection = .myPost

        screens.tabs.showLingering(from: .myPost)

        #expect(screens.tabs.selection == .myPost)
        #expect(screens.tabs.sidebarSelection == .myPost)
        #expect(screens.tabs.lingeringShownIn == .myPost)
    }

    @Test func naamKiezenOpensTheFirstLetterWithoutAName() async throws {
        let toCheck = Self.letter(.review)
        let nameless = Self.letter(.unassigned)
        server.onList { _, filter in
            switch filter.inboxState {
            case .unassigned: [nameless]
            case .review: [toCheck]
            default: []
            }
        }
        let screens = try screens()

        await screens.inbox.load()

        #expect(screens.inbox.firstLetterNeedingName == nameless.id)
    }

    @Test func theScreensAreTiedTogether() async throws {
        server.onTrashList { _ in TrashList(items: []) }
        let screens = try screens()

        #expect(screens.myPost.scope == .myPost && screens.allPost.scope == .all && screens.inbox.scope == .inbox)

        screens.tabs.showSearch()
        #expect(screens.allPost.isSearchPresented)

        await screens.tabs.refreshCounts()
        #expect(screens.myPost.tracksReading && screens.allPost.tracksReading)
        #expect(!screens.inbox.offersReading)

        await screens.inbox.load()
        // The list's load counts the menu again and tells the tabs there is a trash.
        while !screens.tabs.hasTrash { await Task.yield() }
        let counts = server.calls.filter { $0 == .menuCounts(Self.url) }
        #expect(counts.count >= 1)
    }
}

/// "Labels" under Meer: the labels, and the letters of one label as a list of their own.
@MainActor
@Suite struct LabelsTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")

    private let store = ConnectionStore(secrets: InMemorySecretStore())
    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }

    private func screens() throws -> WorkspaceScreens {
        let connection = ServerConnection(urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Jij")
        try store.save(connection, token: "tok")
        return WorkspaceScreens(
            documents: WorkspaceDocuments(workspaceID: UUID(), connection: connection, store: store, server: server),
            uploads: FakeUploadQueue(), canScan: true, camera: FakeScanCamera(.allowed), openSettings: {},
            onTasksChanged: {}, onRevoked: {}, onMissingPairing: {}
        )
    }

    @Test func theLabelsLoad() async throws {
        let screens = try screens()

        await screens.labels.load()

        #expect(screens.labels.state == .loaded)
        #expect(screens.labels.labels == DocumentFixtures.labels)
    }

    @Test func aLabelsLettersAskTheServerForThatLabel() async throws {
        let screens = try screens()
        let label = try #require(DocumentFixtures.labels.first)
        await screens.tabs.refreshCounts()
        let list = screens.allPost.makeLabelModel(label.id)

        await list.load()

        let filters = server.calls.compactMap { if case let .list(_, filter) = $0 { filter } else { nil } }
        #expect(filters.last == DocumentFilter(labelID: label.id))
        #expect(list.scopeTitle == label.name)
        #expect(list.offersReading)
        #expect(!list.offersForWhom && !list.searchIsAvailable)
    }

    @Test func anotherPlaceInTheSidebarStartsWithNothingPushed() throws {
        let tabs = try screens().tabs
        tabs.sidebarSelection = .labels
        tabs.detailPath = NavigationPath([WorkspaceTabsModel.Place.label(UUID())])

        tabs.sidebarSelection = .allPost

        #expect(tabs.detailPath.isEmpty)
    }
}
