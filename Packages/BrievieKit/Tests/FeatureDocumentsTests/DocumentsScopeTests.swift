import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// The scopes of the post list: the inbox, all post, the post of one person.
@MainActor
@Suite struct DocumentsScopeTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")

    private let workspaceID = UUID()
    private let store = ConnectionStore(secrets: InMemorySecretStore())
    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
    private let queue = FakeUploadQueue()

    private func model(server: (any DocumentServer)? = nil) throws -> DocumentsModel {
        let connection = ServerConnection(
            urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn"
        )
        try store.save(connection, token: "tok")
        return DocumentsModel(
            documents: WorkspaceDocuments(
                workspaceID: workspaceID, connection: connection, store: store, server: server ?? self.server
            ),
            uploads: queue, canScan: true, camera: FakeScanCamera(.allowed), openSettings: {}, onRevoked: {},
            onMissingPairing: {}
        )
    }

    private nonisolated static func document(
        _ state: InboxState, status: DocumentStatus = .done, sender: String = "", addressees: [UUID] = [],
        labels: [UUID] = [], suggestions: Int = 0, createdAt: Date = Date(timeIntervalSince1970: 1_794_650_400)
    ) -> DocumentSummary {
        DocumentSummary(
            id: UUID(), clientID: UUID(), status: status, pageCount: 1, createdAt: createdAt, sender: sender,
            documentType: "", letterDate: nil, inboxState: state, addresseeIDs: addressees, labelIDs: labels,
            openSuggestionCount: suggestions
        )
    }

    private var listCalls: [DocumentFilter] {
        server.calls.compactMap { call in
            if case let .list(_, filter) = call { return filter }
            return nil
        }
    }

    @Test func teDoenIsOneListWithWhatIsOnItsWayLast() async throws {
        let review = Self.document(.review, status: .needsReview)
        let unassigned = Self.document(.unassigned)
        let new = Self.document(.new, status: .processing)
        let item = FakeUploadQueue.item(workspaceID: workspaceID)
        queue.set([item])
        server.onList { _ in [new, unassigned, review] }
        let model = try model()

        await model.load()

        #expect(model.scope == .inbox)
        // Same time everywhere: the two that need the person in either order, then the two on their way.
        #expect(Set(model.rows.prefix(2).map(\.id)) == [review.id, unassigned.id])
        #expect(Set(model.rows.suffix(2).map(\.id)) == [item.id, new.id])
        #expect(model.rows.map(\.status.label).sorted() == [
            "Bezig…", "Controleren", "Naam kiezen", "Wacht op verbinding"
        ])
        #expect(model.summary == "Controleren: 1 · Naam kiezen: 1 · Bezig: 2")
        // A 1b server ignores the filter and answers everything: each list keeps only its own state.
        #expect(Set(listCalls.compactMap(\.inboxState?.rawValue)) == ["review", "unassigned", "new"])
    }

    @Test func sortedDocumentsAreNotInTheInbox() async throws {
        let sorted = Self.document(.sorted)
        let review = Self.document(.review, status: .needsReview)
        server.onList { _ in [sorted, review] }
        let model = try model()

        await model.load()
        #expect(model.rows.map(\.id) == [review.id])

        await model.select(.all)
        #expect(Set(model.rows.map(\.id)) == [sorted.id, review.id])
        #expect(model.summary == nil)
    }

    @Test func emptyTeDoenHasNoRows() async throws {
        server.onList { _ in [Self.document(.sorted)] }
        let model = try model()

        await model.load()

        #expect(model.rows.isEmpty)
        #expect(model.emptyText == DocumentStrings.inboxEmpty)
    }

    @Test func personScopeAsksTheServerForThatPerson() async throws {
        let stijn = DocumentFixtures.persons[0]
        let theirs = Self.document(.sorted, addressees: [stijn.id])
        server.onList { _, filter in filter.personID == stijn.id ? [theirs] : [] }
        let model = try model()
        await model.load()

        await model.select(.person(stijn.id))

        #expect(model.scope == .person(stijn.id))
        #expect(listCalls.last == DocumentFilter(personID: stijn.id))
        #expect(model.rows.map(\.id) == [theirs.id])
        #expect(model.scopeTitle == stijn.displayName)
    }

    @Test func rowsCarryNamesAndLabels() async throws {
        let (stijn, anne) = (DocumentFixtures.persons[0], DocumentFixtures.persons[1])
        let (zorg, belasting) = (DocumentFixtures.labels[0], DocumentFixtures.labels[1])
        let document = Self.document(
            .review, status: .needsReview, sender: "CAK", addressees: [anne.id, UUID(), stijn.id],
            labels: [belasting.id, UUID(), zorg.id], suggestions: 2
        )
        server.onList { _ in [document] }
        let model = try model()

        await model.load()

        let row = try #require(model.rows.first)
        // In the order of the loaded lists; ids the lists do not know are skipped.
        #expect(row.addressees == ["Stijn", "Anne"])
        #expect(row.labels == [zorg, belasting])
        #expect(row.hasSuggestions)
        #expect(row.accessibilityLabel.contains("Op naam van Stijn en Anne"))
        #expect(row.accessibilityLabel.contains("Labels: Zorg, Belasting"))
    }

    @Test func a1bServerWithoutPersonsStillShowsThePost() async throws {
        let document = Self.document(.review, status: .needsReview, addressees: [UUID()], labels: [UUID()])
        server.onList { _ in [document] }
        server.onPersons { _ in throw ServerError.other("workspace_not_found") }
        server.onLabels { _ in throw ServerError.other("workspace_not_found") }
        let model = try model()

        await model.load()

        #expect(model.state == .loaded)
        #expect(model.persons.isEmpty)
        #expect(model.labels.isEmpty)
        #expect(model.rows.map(\.id) == [document.id])
        #expect(model.rows.first?.addressees == [])
        #expect(model.scopeTitles.map(\.1) == [DocumentStrings.scopeInbox, DocumentStrings.scopeAll])
    }

    @Test func queuedScansShowInInboxAndAllOnly() async throws {
        let item = FakeUploadQueue.item(workspaceID: workspaceID)
        queue.set([item])
        let stijn = DocumentFixtures.persons[0]
        let model = try model()

        await model.load()
        #expect(model.rows.map(\.id) == [item.id])

        await model.select(.all)
        #expect(model.rows.map(\.id) == [item.id])

        await model.select(.person(stijn.id))
        #expect(model.rows.isEmpty)
    }

    @Test func scopeTitlesListActivePersonsOnly() async throws {
        let archived = Person(id: UUID(), displayName: "Opa", nameVariants: [], isArchived: true)
        server.onPersons { _ in DocumentFixtures.persons + [archived] }
        let model = try model()

        await model.load()

        let stijn = DocumentFixtures.persons[0]
        let anne = DocumentFixtures.persons[1]
        #expect(model.scopeTitles.map(\.0) == [.inbox, .all, .person(stijn.id), .person(anne.id)])
        #expect(model.scopeTitles.map(\.1) == [
            DocumentStrings.scopeInbox, DocumentStrings.scopeAll, "Stijn", "Anne"
        ])
        #expect(model.scopeTitle == DocumentStrings.scopeInbox)
    }

    @Test func unknownInboxStateShowsInAllPostOnly() async throws {
        let unknown = Self.document(.unknown)
        server.onList { _ in [unknown] }
        let model = try model()

        await model.load()
        #expect(model.rows.isEmpty)

        await model.select(.all)
        #expect(model.rows.map(\.id) == [unknown.id])
    }

    @Test func aRefreshTickAsksForTheListOnly() async throws {
        let moving = Self.document(.new, status: .processing)
        server.onList { _ in [moving] }
        let model = try model()
        await model.load()
        let before = server.calls.count

        await model.refreshIfNeeded()

        #expect(server.calls.count == before + 1)
        guard case .list = server.calls.last else {
            Issue.record("expected a list call")
            return
        }
    }

    @Test func aPersonTheServerNoLongerKnowsFallsBackToTheInbox() async throws {
        let stijn = DocumentFixtures.persons[0]
        server.onList { _, filter in
            if filter.personID != nil { throw ServerError.other("person_not_found") }
            return []
        }
        let model = try model()
        await model.load()

        await model.select(.person(stijn.id))

        #expect(model.scope == .inbox)
        #expect(model.state == .loaded)
    }

    @Test func anArchivedPersonFallsBackToTheInbox() async throws {
        let stijn = DocumentFixtures.persons[0]
        let model = try model()
        await model.load()
        server.onPersons { _ in
            [Person(id: stijn.id, displayName: stijn.displayName, nameVariants: [], isArchived: true)]
        }

        await model.select(.person(stijn.id))

        #expect(model.scope == .inbox)
        #expect(model.state == .loaded)
    }

    @Test(arguments: [false, true])
    func aSlowAnswerForAnEarlierScopeNeverTouchesTheCurrentOne(earlierFails: Bool) async throws {
        let (stijn, anne) = (DocumentFixtures.persons[0], DocumentFixtures.persons[1])
        let stijnsLetter = Self.document(.sorted, addressees: [stijn.id])
        let annesLetter = Self.document(.sorted, addressees: [anne.id])
        server.onList { _, filter in
            switch filter.personID {
            case stijn.id:
                if earlierFails { throw ServerError.unreachable }
                return [stijnsLetter]
            case anne.id: return [annesLetter]
            default: return []
            }
        }
        let gated = GatedDocumentServer(server)
        let model = try model(server: gated)
        await model.load()
        gated.close(stijn.id)
        gated.close(anne.id)

        let toStijn = Task { await model.select(.person(stijn.id)) }
        while !gated.isWaiting(stijn.id) { await Task.yield() }
        let toAnne = Task { await model.select(.person(anne.id)) }
        while !gated.isWaiting(anne.id) { await Task.yield() }

        // Stijn's answer arrives while Anne's list is still on its way: nothing changes for Anne.
        gated.open(stijn.id)
        await toStijn.value
        #expect(model.scope == .person(anne.id))
        #expect(model.state == .loading)
        #expect(model.rows.isEmpty)

        gated.open(anne.id)
        await toAnne.value
        #expect(model.state == .loaded)
        #expect(model.rows.map(\.id) == [annesLetter.id])
    }
}

/// Where the inbox names its workspace: in the subtitle from iOS 26, in the title before it, and nowhere when
/// the user has one workspace.
@Suite struct DocumentsTitleTests {
    @Test func withOneWorkspaceTheTitleIsTheScope() {
        #expect(DocumentStrings.navigationTitle(scope: "Te doen", workspace: nil, hasSubtitle: false) == "Te doen")
        #expect(DocumentStrings.navigationTitle(scope: "Te doen", workspace: nil, hasSubtitle: true) == "Te doen")
    }

    @Test func withASubtitleTheWorkspaceGoesThere() {
        #expect(DocumentStrings.navigationTitle(scope: "Alle post", workspace: "Zaak", hasSubtitle: true)
            == "Alle post")
    }

    @Test func withoutASubtitleTheTitleNamesTheWorkspace() {
        #expect(DocumentStrings.navigationTitle(scope: "Te doen", workspace: "Thuis", hasSubtitle: false)
            == "Te doen · Thuis")
    }
}
