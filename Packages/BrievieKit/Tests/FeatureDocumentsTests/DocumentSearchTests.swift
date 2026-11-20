import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// Search in "Alle post": one request per pause in typing, a newer term cancels the older request, clear states,
/// and nothing of the term is kept once the session ends or the user leaves "Alle post".
@MainActor
@Suite struct DocumentSearchTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")

    private let store = ConnectionStore(secrets: InMemorySecretStore())
    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
    private let queue = FakeUploadQueue()
    private let events = EventLog()

    private func model(
        server: (any DocumentServer)? = nil, delay: Duration = .milliseconds(20)
    ) throws -> DocumentsModel {
        let connection = ServerConnection(
            urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Testgebruiker"
        )
        try store.save(connection, token: "tok")
        return DocumentsModel(
            documents: WorkspaceDocuments(
                workspaceID: UUID(), connection: connection, store: store, server: server ?? self.server
            ),
            uploads: queue, canScan: true, camera: FakeScanCamera(.allowed), openSettings: {},
            onRevoked: { [events] in events.add("revoked") },
            onMissingPairing: { [events] in events.add("missing") },
            searchDelay: delay
        )
    }

    private nonisolated static func hit(
        sender: String, labels: [UUID] = [], snippet: [SnippetPart] = []
    ) -> DocumentSearchHit {
        DocumentSearchHit(
            document: DocumentSummary(
                id: UUID(), clientID: UUID(), status: .done, pageCount: 2,
                createdAt: Date(timeIntervalSince1970: 1_794_650_400), sender: sender, documentType: "invoice",
                letterDate: nil, labelIDs: labels
            ),
            snippet: snippet
        )
    }

    private var searchedTerms: [String] {
        server.calls.compactMap { call in
            if case let .search(_, query) = call { return query.text }
            return nil
        }
    }

    @Test func startsIdleWithoutATerm() throws {
        let search = try model().search

        #expect(search.state == .idle)
        #expect(search.query.isEmpty)
        #expect(search.hits.isEmpty)
        #expect(!search.isActive)
    }

    @Test func typingSearchesOnceAfterThePause() async throws {
        server.onSearch { _, _ in DocumentSearchPage(hits: [Self.hit(sender: "Waterbedrijf Voorbeeld")]) }
        let search = try model().search

        search.query = "w"
        search.query = "wa"
        search.query = "wat"
        #expect(search.state == .searching)
        await search.settle()

        #expect(searchedTerms == ["wat"])
        #expect(search.state == .results)
        #expect(search.hits.map(\.row.title) == ["Waterbedrijf Voorbeeld"])
    }

    @Test func oneCharacterIsTooShortAndAsksNothing() async throws {
        let search = try model().search

        search.query = " a "
        await search.settle()

        #expect(search.state == .tooShort)
        #expect(searchedTerms.isEmpty)
    }

    @Test func theTermIsTrimmedAndCutAtTheServersLimit() async throws {
        let search = try model().search

        search.query = "  " + String(repeating: "b", count: 250) + "  "
        await search.settle()

        #expect(searchedTerms == [String(repeating: "b", count: DocumentSearchQuery.maxLength)])
    }

    @Test func spacesOnlyAreNoSearch() async throws {
        let search = try model().search

        search.query = "    "
        await search.settle()

        #expect(search.state == .idle)
        #expect(searchedTerms.isEmpty)
    }

    @Test func clearingTheFieldEmptiesTheResults() async throws {
        server.onSearch { _, _ in DocumentSearchPage(hits: [Self.hit(sender: "Gemeente Voorbeeld")]) }
        let search = try model().search
        search.query = "gemeente"
        await search.settle()

        search.query = ""

        #expect(search.state == .idle)
        #expect(search.hits.isEmpty)
    }

    @Test func noHitsSaysNothingWasFound() async throws {
        let search = try model().search

        search.query = "onbekend"
        await search.settle()

        #expect(search.state == .noResults)
        #expect(search.hits.isEmpty)
    }

    @Test func aNewerTermCancelsTheRequestThatIsStillRunning() async throws {
        let inner = server
        inner.onSearch { _, query in
            DocumentSearchPage(hits: [Self.hit(sender: query.text == "belasting" ? "Oud" : "Nieuw")])
        }
        let gated = GatedDocumentServer(inner)
        gated.close(gate: .search("belasting"))
        let search = try model(server: gated).search

        search.query = "belasting"
        while !gated.isWaiting(gate: .search("belasting")) { await Task.yield() }
        search.query = "belastingdienst"
        gated.open(gate: .search("belasting"))
        await search.settle()

        #expect(search.hits.map(\.row.title) == ["Nieuw"])
        #expect(search.state == .results)
        #expect(gated.searchWasCancelled("belasting"))
    }

    @Test func showsTheFragmentAndTheRowOfTheList() async throws {
        let label = try #require(DocumentFixtures.labels.first)
        let snippet = [SnippetPart(text: "Uw ", isHit: false), SnippetPart(text: "aanslag", isHit: true)]
        server.onSearch { _, _ in
            DocumentSearchPage(hits: [Self.hit(sender: "Belastingdienst", labels: [label.id], snippet: snippet)])
        }
        let model = try model()
        await model.select(.all)

        model.search.query = "aanslag"
        await model.search.settle()

        let hit = try #require(model.search.hits.first)
        #expect(hit.snippet == snippet)
        #expect(hit.snippetText == "Uw aanslag")
        #expect(hit.row.labels == [label])
        #expect(hit.row.status == .done)
    }

    @Test func saysWhenTheMatchIsOnlyApproximateOrABSNWasRemoved() async throws {
        server.onSearch { _, _ in
            DocumentSearchPage(hits: [Self.hit(sender: "Verzekeraar Voorbeeld")], isFuzzy: true, bsnRemoved: true)
        }
        let search = try model().search

        search.query = "verzekring 123456782"
        await search.settle()

        #expect(search.isFuzzy)
        #expect(search.bsnRemoved)
    }

    @Test func aBSNAloneFindsNothingAndSaysWhy() async throws {
        server.onSearch { _, _ in DocumentSearchPage(hits: [], bsnRemoved: true) }
        let search = try model().search

        search.query = "123456782"
        await search.settle()

        #expect(search.state == .noResults)
        #expect(search.bsnRemoved)
    }

    @Test func loadsTheNextPageBehindTheFirst() async throws {
        server.onSearch { _, query in
            query.offset == 0
                ? DocumentSearchPage(hits: [Self.hit(sender: "Eerste")], nextOffset: 30)
                : DocumentSearchPage(hits: [Self.hit(sender: "Tweede")])
        }
        let search = try model().search
        search.query = "brief"
        await search.settle()
        #expect(search.canLoadMore)

        await search.loadMore()

        #expect(search.hits.map(\.row.title) == ["Eerste", "Tweede"])
        #expect(!search.canLoadMore)
        let offsets = server.calls.compactMap { call -> Int? in
            if case let .search(_, query) = call { return query.offset }
            return nil
        }
        #expect(offsets == [0, 30])
    }

    @Test func aFailureShowsAMessageAndRetrySearchesAgain() async throws {
        server.onSearch { _, _ in throw ServerError.unreachable }
        let search = try model().search
        search.query = "energie"
        await search.settle()
        #expect(search.state == .failed(message: DocumentStrings.unreachable))

        server.onSearch { _, _ in DocumentSearchPage(hits: [Self.hit(sender: "Energie Voorbeeld")]) }
        search.retry()
        await search.settle()

        #expect(search.state == .results)
        #expect(searchedTerms == ["energie", "energie"])
    }

    @Test func tooManySearchesAsksToWait() async throws {
        server.onSearch { _, _ in throw ServerError.tooManyAttempts }
        let search = try model().search

        search.query = "energie"
        await search.settle()

        #expect(search.state == .failed(message: DocumentStrings.searchTooMany))
    }

    @Test func aServerWithoutSearchSaysSo() async throws {
        server.onSearch { _, _ in throw ServerError.other("http_404") }
        let search = try model().search

        search.query = "energie"
        await search.settle()

        #expect(search.state == .failed(message: DocumentStrings.searchNotSupported))
    }

    @Test func aRevokedDeviceEndsTheSessionAndForgetsTheTerm() async throws {
        server.onSearch { _, _ in throw ServerError.unauthorized }
        let search = try model().search

        search.query = "huur"
        await search.settle()

        #expect(events.all == ["revoked"])
        #expect(search.query.isEmpty)
        #expect(search.state == .idle)
    }

    @Test func aMissingPairingForgetsTheTerm() async throws {
        let search = try model().search
        try store.clear()

        search.query = "huur"
        await search.settle()

        #expect(events.all == ["missing"])
        #expect(search.query.isEmpty)
    }

    @Test func leavingAllePostForgetsTheSearch() async throws {
        server.onSearch { _, _ in DocumentSearchPage(hits: [Self.hit(sender: "Huurbaas Voorbeeld")]) }
        let model = try model()
        await model.select(.all)
        model.search.query = "huur"
        await model.search.settle()
        #expect(model.search.isActive)

        await model.select(.inbox)

        #expect(model.search.query.isEmpty)
        #expect(model.search.hits.isEmpty)
        #expect(model.search.state == .idle)
        #expect(!model.searchIsAvailable)
    }

    @Test func forgettingWhileARequestRunsDropsItsAnswer() async throws {
        server.onSearch { _, _ in DocumentSearchPage(hits: [Self.hit(sender: "Laat")]) }
        let gated = GatedDocumentServer(server)
        gated.close(gate: .search("laat"))
        let search = try model(server: gated).search

        search.query = "laat"
        while !gated.isWaiting(gate: .search("laat")) { await Task.yield() }
        search.forget()
        gated.open(gate: .search("laat"))
        await search.settle()

        #expect(search.hits.isEmpty)
        #expect(search.state == .idle)
    }

    @Test func searchingIsOnlyOfferedInAllePost() async throws {
        let model = try model()
        #expect(!model.searchIsAvailable)

        await model.select(.all)

        #expect(model.searchIsAvailable)
    }

    @Test func submittingSearchesAtOnce() async throws {
        let search = try model(delay: .seconds(60)).search

        search.query = "polis"
        search.submit()
        await search.settle()

        #expect(searchedTerms == ["polis"])
    }
}
