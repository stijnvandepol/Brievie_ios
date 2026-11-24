import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// "Mijn post" and "Ongelezen": the own letters, the unread mark, and marking letters read or unread by hand.
@MainActor
@Suite struct DocumentsReadingTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")

    private let store = ConnectionStore(secrets: InMemorySecretStore())
    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
    private let events = EventLog()

    private func model(_ scope: DocumentsModel.Scope, tracksReading: Bool = true) throws -> DocumentsModel {
        let connection = ServerConnection(urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Jij")
        try store.save(connection, token: "tok")
        let model = DocumentsModel(
            documents: WorkspaceDocuments(workspaceID: UUID(), connection: connection, store: store, server: server),
            scope: scope, uploads: FakeUploadQueue(), canScan: true, camera: FakeScanCamera(.allowed),
            openSettings: {}, onRevoked: {}, onMissingPairing: {}
        )
        model.tracksReading = tracksReading
        let events = events
        model.onListChanged = { events.add("changed") }
        return model
    }

    private nonisolated static func letter(unread: Bool, state: InboxState = .sorted) -> DocumentSummary {
        DocumentSummary(
            id: UUID(), clientID: UUID(), status: .done, pageCount: 1, createdAt: Date(timeIntervalSince1970: 1),
            sender: "Gemeente", documentType: "", letterDate: nil, inboxState: state, isUnread: unread
        )
    }

    private var lists: [DocumentFilter] {
        server.calls.compactMap { if case let .list(_, filter) = $0 { filter } else { nil } }
    }

    private var markCalls: [FakeDocumentServer.Call] {
        server.calls.filter {
            switch $0 {
            case .markRead, .markUnread, .markManyRead: true
            default: false
            }
        }
    }

    @Test func myPostAsksForTheOwnLettersAndShowsWhatIsUnread() async throws {
        let unread = Self.letter(unread: true)
        let read = Self.letter(unread: false)
        server.onList { _ in [unread, read] }
        let model = try model(.myPost)

        await model.load()

        #expect(lists == [DocumentFilter(addressedToMe: true)])
        let unreadRow = try #require(model.rows.first { $0.id == unread.id })
        let readRow = try #require(model.rows.first { $0.id == read.id })
        #expect(unreadRow.isUnread && !readRow.isUnread)
        #expect(unreadRow.accessibilityLabel.hasPrefix("Ongelezen, Gemeente"))
        #expect(!readRow.accessibilityLabel.contains("Ongelezen"))
        #expect(model.hasUnreadRows)
        #expect(model.offersReading)
    }

    @Test func theInboxNeverShowsUnread() async throws {
        server.onList { _, _ in [Self.letter(unread: true, state: .review)] }
        let model = try model(.inbox)

        await model.load()

        #expect(model.rows.allSatisfy { !$0.isUnread })
        #expect(!model.offersReading)
    }

    @Test func unreadOnlyAsksTheServerForUnreadLetters() async throws {
        let model = try model(.myPost)
        await model.load()

        await model.select(.myPostUnread)

        #expect(lists.last == DocumentFilter(addressedToMe: true, unreadOnly: true))
        #expect(model.scopeTitle == "Mijn post")
        #expect(model.emptyText == DocumentStrings.myPostAllRead)
    }

    @Test func markingReadShowsAtOnceAndTellsTheServer() async throws {
        let unread = Self.letter(unread: true)
        server.onList { _ in [unread] }
        let model = try model(.myPost)
        await model.load()
        let before = events.all.count

        await model.markRead(unread.id)

        #expect(markCalls == [.markRead(Self.url, unread.id)])
        #expect(model.rows.map(\.isUnread) == [false])
        #expect(events.all.dropFirst(before) == ["changed"])

        await model.markUnread(unread.id)

        #expect(markCalls.last == .markUnread(Self.url, unread.id))
        #expect(model.rows.map(\.isUnread) == [true])
    }

    @Test func aFailedMarkPutsTheRowBackAndSaysWhy() async throws {
        let unread = Self.letter(unread: true)
        server.onList { _ in [unread] }
        server.onMarkRead { _, _ in throw ServerError.unreachable }
        let model = try model(.myPost)
        await model.load()

        await model.markRead(unread.id)

        #expect(model.rows.map(\.isUnread) == [true])
        #expect(model.readingError == DocumentStrings.unreachable)
    }

    @Test func anOlderServerStopsOfferingIt() async throws {
        let unread = Self.letter(unread: true)
        server.onList { _ in [unread] }
        server.onMarkRead { _, _ in throw ServerError.other("http_404") }
        let model = try model(.all)
        await model.load()

        await model.markRead(unread.id)

        #expect(!model.offersReading)
        #expect(model.readingError == nil)
    }

    @Test func nothingIsOfferedBeforeTheServerSaidItKeepsMarks() async throws {
        let unread = Self.letter(unread: true)
        server.onList { _ in [unread] }
        let model = try model(.all, tracksReading: false)
        await model.load()

        await model.markRead(unread.id)

        #expect(!model.offersReading)
        #expect(markCalls.isEmpty)
    }

    @Test func allReadSendsOnlyTheUnreadLettersOnScreen() async throws {
        let first = Self.letter(unread: true)
        let second = Self.letter(unread: true)
        let read = Self.letter(unread: false)
        server.onList { _ in [first, second, read] }
        let model = try model(.myPost)
        await model.load()

        await model.markAllRead()

        guard case let .markManyRead(_, ids) = markCalls.first else {
            Issue.record("no markDocumentsRead")
            return
        }
        #expect(Set(ids) == [first.id, second.id])
        #expect(!model.hasUnreadRows)
    }

    @Test func inUnreadOnlyAReadLetterLeavesTheList() async throws {
        let unread = Self.letter(unread: true)
        server.onList { _ in [unread] }
        let model = try model(.myPostUnread)
        await model.load()

        model.didRead(unread.id)

        #expect(model.rows.isEmpty)
    }

    @Test func anOpenedLetterIsReadInTheList() async throws {
        let unread = Self.letter(unread: true)
        server.onList { _ in [unread] }
        let model = try model(.all)
        await model.load()
        let before = events.all.count

        model.didRead(unread.id)
        model.didRead(unread.id)

        #expect(model.rows.map(\.isUnread) == [false])
        // Only a change counts the menu again.
        #expect(events.all.dropFirst(before) == ["changed"])
        #expect(markCalls.isEmpty)
    }
}

/// Opening a letter marks it read on the server, once per opening.
@MainActor
@Suite struct ReviewReadingTests {
    private let harness = ReviewHarness()

    @Test func theLetterIsMarkedReadOnceWhenItsScreenLoads() async throws {
        let model = try harness.model()
        let events = harness.events
        model.onRead = { events.add("read") }

        await model.load()
        await model.load()

        let marks = harness.server.calls.filter { if case .markRead = $0 { true } else { false } }
        #expect(marks.count == 1)
        #expect(events.all.filter { $0 == "read" } == ["read"])
    }

    @Test func anOlderServerOpensTheLetterAsBefore() async throws {
        harness.server.onMarkRead { _, _ in throw ServerError.other("http_404") }
        let model = try harness.model()
        let events = harness.events
        model.onRead = { events.add("read") }

        await model.load()

        #expect(model.state == .review)
        #expect(!events.all.contains("read"))
    }
}
