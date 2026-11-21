import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// "Dubbel?" in "Te doen": asked only when the server counts pairs, never on the refresh tick, the chip on a
/// letter, and the notices after a choice on the compare screen.
@MainActor
@Suite struct DocumentsDuplicatesTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")
    private static let dutch = Locale(identifier: "nl_NL")

    private let workspaceID = UUID()
    private let store = ConnectionStore(secrets: InMemorySecretStore())
    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
    private let queue = FakeUploadQueue()

    private func model() throws -> DocumentsModel {
        let connection = ServerConnection(
            urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn"
        )
        try store.save(connection, token: "tok")
        return DocumentsModel(
            documents: WorkspaceDocuments(
                workspaceID: workspaceID, connection: connection, store: store, server: server
            ),
            uploads: queue, canScan: true, camera: FakeScanCamera(.allowed), openSettings: {},
            onRevoked: {}, onMissingPairing: {}, locale: Self.dutch
        )
    }

    private var duplicatesCalls: Int {
        server.calls.count { if case .duplicates = $0 { true } else { false } }
    }

    private nonisolated static func letter(
        _ sender: String, day: Int? = nil, inbox: InboxState = .review
    ) -> DocumentSummary {
        DocumentSummary(
            id: UUID(), clientID: UUID(), status: inbox == .sorted ? .done : .needsReview, pageCount: 1,
            createdAt: Date(timeIntervalSince1970: 1_794_650_400), sender: sender, documentType: "",
            letterDate: day.map { CalendarDate(year: 2026, month: 11, day: $0) }, inboxState: inbox
        )
    }

    private func countPairs(_ count: Int) {
        server.onInboxCounts { _ in InboxCounts(new: 0, review: 0, unassigned: 0, duplicate: count) }
    }

    @Test func theInboxAsksForPairsOnlyWhenTheServerCountsThem() async throws {
        countPairs(0)
        let none = try model()
        await none.load()
        #expect(duplicatesCalls == 0)
        #expect(none.duplicates.isEmpty)

        let pairs = [
            DocumentFixtures.pair(first: Self.letter("A"), second: Self.letter("A")),
            DocumentFixtures.pair(first: Self.letter("B"), second: Self.letter("B"))
        ]
        server.onDuplicates { _ in pairs }
        countPairs(2)
        let some = try model()
        await some.load()

        #expect(duplicatesCalls == 1)
        #expect(some.duplicates.map(\.id) == pairs.map(\.id))
    }

    @Test func anOlderServerShowsNoDuplicateGroup() async throws {
        // The fake's own counts carry no pairs, as a server before host PR #34; its letters no count either.
        server.onList { _ in [Self.letter("CAK")] }
        let model = try model()

        await model.load()

        #expect(duplicatesCalls == 0)
        #expect(model.duplicates.isEmpty)
        #expect(model.rows.allSatisfy { !$0.isPossibleDuplicate })
    }

    @Test func aFailingPairListLeavesTheRestOfTheInbox() async throws {
        server.onList { _, filter in filter.inboxState == .review ? [Self.letter("CAK")] : [] }
        server.onDuplicates { _ in throw ServerError.unreachable }
        countPairs(1)
        let model = try model()

        await model.load()

        #expect(model.state == .loaded)
        #expect(model.rows.map(\.title) == ["CAK"])
        #expect(model.duplicates.isEmpty)
    }

    @Test func theRefreshTickDoesNotAskForPairs() async throws {
        server.onDuplicates { _ in [DocumentFixtures.pair(first: Self.letter("A"), second: Self.letter("A"))] }
        countPairs(1)
        queue.set([FakeUploadQueue.item(workspaceID: workspaceID)])
        let model = try model()
        await model.load()
        #expect(duplicatesCalls == 1)

        await model.refreshIfNeeded()

        #expect(duplicatesCalls == 1)
        #expect(model.duplicates.count == 1)
    }

    @Test func pairRowsNameBothLettersAndTheSimilarity() async throws {
        let pair = DocumentFixtures.pair(
            first: Self.letter("Gemeente Voorbeelddorp", day: 3), second: Self.letter("", day: nil)
        )
        server.onDuplicates { _ in [pair] }
        countPairs(1)
        let model = try model()

        await model.load()

        let row = try #require(model.duplicates.first)
        #expect(row.first == "Gemeente Voorbeelddorp, 3 november 2026")
        #expect(row.second.hasPrefix("Onbekende afzender, Gescand op "))
        #expect(row.similarity == "Lijkt op elkaar voor 92%")
        #expect(row.accessibilityLabel.contains("Gemeente Voorbeelddorp, 3 november 2026"))
        #expect(row.accessibilityLabel.contains("Lijkt op elkaar voor 92%"))
    }

    @Test func rowsWithAnOpenPairCarryTheChip() async throws {
        let marked = DocumentSummary(
            id: UUID(), clientID: UUID(), status: .done, pageCount: 1, createdAt: .now, sender: "CAK",
            documentType: "", letterDate: nil, openDuplicateCount: 1
        )
        server.onList { _ in [marked, Self.letter("Belastingdienst", inbox: .sorted)] }
        let model = try model()

        await model.select(.all)

        let row = try #require(model.rows.first { $0.title == "CAK" })
        #expect(row.isPossibleDuplicate)
        #expect(row.accessibilityLabel.contains("Dubbel?"))
        let other = try #require(model.rows.first { $0.title == "Belastingdienst" })
        #expect(!other.isPossibleDuplicate)
        #expect(!other.accessibilityLabel.contains("Dubbel?"))
    }

    @Test func theInboxIsNotEmptyWhileItHasPairs() async throws {
        server.onList { _ in [] }
        server.onDuplicates { _ in [DocumentFixtures.pair(first: Self.letter("A"), second: Self.letter("A"))] }
        countPairs(1)
        let model = try model()

        await model.load()

        #expect(model.rows.isEmpty)
        #expect(!model.showsEmpty)

        countPairs(0)
        await model.load()
        #expect(model.showsEmpty)
    }

    @Test func anotherScopeHasNoPairs() async throws {
        server.onDuplicates { _ in [DocumentFixtures.pair(first: Self.letter("A"), second: Self.letter("A"))] }
        countPairs(1)
        let model = try model()
        await model.load()
        await model.didDismissDuplicate()
        #expect(model.duplicates.count == 1)

        await model.select(.all)

        #expect(model.duplicates.isEmpty)
        #expect(model.duplicateNotice == nil)
        #expect(duplicatesCalls == 2)
    }

    @Test func dismissShowsTheNoticeOnTeDoen() async throws {
        let model = try model()
        await model.load()

        await model.didDismissDuplicate()

        #expect(model.duplicateNotice == "Goed. We vragen het niet meer voor deze twee brieven.")
        model.closeDuplicateNotice()
        #expect(model.duplicateNotice == nil)
    }

    @Test func aPairDecidedElsewhereSaysSoAndReloads() async throws {
        let model = try model()
        await model.load()
        let listsBefore = server.calls.count { if case .list = $0 { true } else { false } }

        await model.didFindPairDecided()

        #expect(model.duplicateNotice == "Over deze twee brieven is al gekozen.")
        #expect(server.calls.count { if case .list = $0 { true } else { false } } > listsBefore)
    }

    @Test func undoAfterAMergeRestoresTheOtherLetter() async throws {
        let other = UUID()
        let model = try model()
        await model.load()

        await model.didMerge(trashed: other)
        #expect(model.undo?.documentID == other)
        #expect(model.undo?.message == "De brief staat in de prullenbak.")

        await model.undoTrash()

        #expect(server.calls.contains(.restore(Self.url, other)))
        #expect(model.undo == nil)
    }
}
