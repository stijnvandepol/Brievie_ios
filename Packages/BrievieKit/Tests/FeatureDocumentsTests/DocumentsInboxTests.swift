import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// The inbox: one list per inbox state, the counts for the headers, the refresh tick and slow answers.
@MainActor
@Suite struct DocumentsInboxTests {
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
        _ state: InboxState, status: DocumentStatus = .done, addressees: [UUID] = []
    ) -> DocumentSummary {
        DocumentSummary(
            id: UUID(), clientID: UUID(), status: status, pageCount: 1,
            createdAt: Date(timeIntervalSince1970: 1_794_650_400), sender: "", documentType: "", letterDate: nil,
            inboxState: state, addresseeIDs: addressees
        )
    }

    private var listCalls: [DocumentFilter] {
        server.calls.compactMap { call in
            if case let .list(_, filter) = call { return filter }
            return nil
        }
    }

    private static func inboxFilters(_ filters: [DocumentFilter]) -> [InboxState] {
        let order: [InboxState] = [.review, .unassigned, .new]
        return filters.compactMap(\.inboxState).sorted { lhs, rhs in
            (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }

    private var countCalls: Int {
        server.calls.count { call in
            if case .inboxCounts = call { return true }
            return false
        }
    }

    @Test func theInboxAsksTheServerPerStateAndForTheCounts() async throws {
        let reviews = (0..<200).map { _ in Self.document(.review, status: .needsReview) }
        let unassigned = Self.document(.unassigned)
        server.onList { _, filter in
            switch filter.inboxState {
            case .review: reviews
            case .unassigned: [unassigned]
            default: []
            }
        }
        server.onInboxCounts { _ in InboxCounts(new: 0, review: 212, unassigned: 1) }
        let model = try model()

        await model.load()

        #expect(listCalls.allSatisfy { $0.personID == nil && $0.inboxState != nil })
        #expect(Self.inboxFilters(listCalls) == [.review, .unassigned, .new])
        #expect(countCalls == 1)
        #expect(model.rows.count == 201)
        #expect(model.summary == "Controleren: 212 (de nieuwste 200) · Naam kiezen: 1")
    }

    @Test func withoutCountsTheSummaryCountsTheLettersShown() async throws {
        let reviews = (0..<200).map { _ in Self.document(.review, status: .needsReview) }
        server.onList { _, filter in filter.inboxState == .review ? reviews : [] }
        server.onInboxCounts { _ in throw ServerError.other("not_found") }
        let model = try model()

        await model.load()

        #expect(model.state == .loaded)
        #expect(model.summary == "Controleren: 200")
    }

    @Test func aCountAboveAShortListIsNotBelieved() async throws {
        // Fewer letters than the server's limit is the whole state: a count that differs is out of date.
        let review = Self.document(.review, status: .needsReview)
        server.onList { _, filter in filter.inboxState == .review ? [review] : [] }
        server.onInboxCounts { _ in InboxCounts(new: 0, review: 5, unassigned: 0) }
        let model = try model()

        await model.load()

        #expect(model.summary == "Controleren: 1")
    }

    @Test func aRefreshTickInTheInboxAsksForTheLettersOnTheirWayOnly() async throws {
        let moving = Self.document(.new, status: .processing)
        let review = Self.document(.review, status: .needsReview)
        server.onList { _, filter in
            switch filter.inboxState {
            case .new: [moving]
            case .review: [review]
            default: []
            }
        }
        let model = try model()
        await model.load()
        let before = server.calls.count

        await model.refreshIfNeeded()

        #expect(server.calls.count == before + 1)
        #expect(listCalls.last == DocumentFilter(inboxState: .new))
        #expect(model.rows.map(\.id) == [review.id, moving.id])
    }

    @Test func aLetterThatLeftOnderwegReloadsTheWholeInboxOnce() async throws {
        let moving = Self.document(.new, status: .processing)
        server.onList { _, filter in filter.inboxState == .new ? [moving] : [] }
        let model = try model()
        await model.load()
        let done = DocumentSummary(
            id: moving.id, clientID: moving.clientID, status: .needsReview, pageCount: 1, createdAt: moving.createdAt,
            sender: "", documentType: "", letterDate: nil, inboxState: .review
        )
        server.onList { _, filter in filter.inboxState == .review ? [done] : [] }
        let before = listCalls.count

        await model.refreshIfNeeded()

        // The tick's one list, then the three of the whole inbox.
        #expect(listCalls.count == before + 4)
        #expect(model.rows.map(\.status) == [.needsReview])
        #expect(model.rows.map(\.id) == [moving.id])
        #expect(!model.needsRefresh)
    }

    @Test func aSlowInboxAnswerNeverTouchesAPersonChosenMeanwhile() async throws {
        let anne = DocumentFixtures.persons[1]
        let review = Self.document(.review, status: .needsReview)
        let annesLetter = Self.document(.sorted, addressees: [anne.id])
        server.onList { _, filter in
            if filter.personID == anne.id { return [annesLetter] }
            return filter.inboxState == .review ? [review] : []
        }
        let gated = GatedDocumentServer(server)
        let model = try model(server: gated)
        await model.load()
        await model.select(.all)
        gated.close(gate: .inbox(.review))
        gated.close(anne.id)

        let toInbox = Task { await model.select(.inbox) }
        while !gated.isWaiting(gate: .inbox(.review)) { await Task.yield() }
        let toAnne = Task { await model.select(.person(anne.id)) }
        while !gated.isWaiting(anne.id) { await Task.yield() }

        gated.open(gate: .inbox(.review))
        await toInbox.value
        #expect(model.scope == .person(anne.id))
        #expect(model.state == .loading)
        #expect(model.rows.isEmpty)

        gated.open(anne.id)
        await toAnne.value
        #expect(model.state == .loaded)
        #expect(model.rows.map(\.id) == [annesLetter.id])
    }

    @Test(arguments: [false, true])
    func aSlowPersonAnswerNeverTouchesTheInbox(earlierFails: Bool) async throws {
        let stijn = DocumentFixtures.persons[0]
        let review = Self.document(.review, status: .needsReview)
        let stijnsLetter = Self.document(.sorted, addressees: [stijn.id])
        server.onList { _, filter in
            if filter.personID == stijn.id {
                if earlierFails { throw ServerError.unreachable }
                return [stijnsLetter]
            }
            return filter.inboxState == .review ? [review] : []
        }
        let gated = GatedDocumentServer(server)
        let model = try model(server: gated)
        await model.select(.all)
        gated.close(stijn.id)

        let toStijn = Task { await model.select(.person(stijn.id)) }
        while !gated.isWaiting(stijn.id) { await Task.yield() }
        await model.select(.inbox)
        #expect(model.rows.map(\.id) == [review.id])

        gated.open(stijn.id)
        await toStijn.value
        #expect(model.scope == .inbox)
        #expect(model.state == .loaded)
        #expect(model.rows.map(\.status) == [.needsReview])
        #expect(model.rows.map(\.id) == [review.id])
    }
}
