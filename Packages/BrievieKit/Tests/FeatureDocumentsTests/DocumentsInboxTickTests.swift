import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// The inbox's refresh tick and the order of loads: never half an inbox, never a stale answer over a newer one.
@MainActor
@Suite struct DocumentsInboxTickTests {
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
        _ state: InboxState, status: DocumentStatus, clientID: UUID = UUID()
    ) -> DocumentSummary {
        DocumentSummary(
            id: UUID(), clientID: clientID, status: status, pageCount: 1,
            createdAt: Date(timeIntervalSince1970: 1_794_650_400), sender: "", documentType: "", letterDate: nil,
            inboxState: state
        )
    }

    private var listCalls: [DocumentFilter] {
        server.calls.compactMap { call in
            if case let .list(_, filter) = call { return filter }
            return nil
        }
    }

    @Test func aScanProcessedWithinOneTickStillShowsUp() async throws {
        let item = FakeUploadQueue.item(workspaceID: workspaceID)
        queue.set([item])
        let model = try model()
        await model.load()
        #expect(model.rows.map(\.id) == [item.id])
        // Uploaded and read by the server before the tick: never "new" on this phone.
        let arrived = Self.document(.review, status: .needsReview, clientID: item.id)
        queue.set([])
        server.onList { _, filter in filter.inboxState == .review ? [arrived] : [] }
        let before = listCalls.count

        await model.refreshIfNeeded()

        #expect(listCalls.count == before + 4)
        #expect(model.rows.map(\.status) == [.needsReview])
        #expect(model.rows.map(\.id) == [arrived.id])
    }

    @Test func aTickAfterAFailedFirstLoadLoadsTheWholeInbox() async throws {
        queue.set([FakeUploadQueue.item(workspaceID: workspaceID)])
        server.onList { _ in throw ServerError.unreachable }
        let model = try model()
        await model.load()
        #expect(model.state == .failed(message: DocumentStrings.unreachable))

        // Still failing: the error stays.
        await model.refreshIfNeeded()
        #expect(model.state == .failed(message: DocumentStrings.unreachable))

        let review = Self.document(.review, status: .needsReview)
        server.onList { _, filter in filter.inboxState == .review ? [review] : [] }
        await model.refreshIfNeeded()

        #expect(model.state == .loaded)
        #expect(model.rows.map(\.status) == [.needsReview, .waitingForUpload])
        #expect(Set(listCalls.suffix(3).compactMap(\.inboxState?.rawValue)) == ["review", "unassigned", "new"])
    }

    @Test func aTickWhileTheFirstLoadRunsShowsNoHalfInbox() async throws {
        queue.set([FakeUploadQueue.item(workspaceID: workspaceID)])
        let review = Self.document(.review, status: .needsReview)
        server.onList { _, filter in filter.inboxState == .review ? [review] : [] }
        let gated = GatedDocumentServer(server)
        let model = try model(server: gated)
        gated.close(gate: .inbox(.review))
        let first = Task { await model.load() }
        while !gated.isWaiting(gate: .inbox(.review)) { await Task.yield() }
        #expect(model.needsRefresh)

        let ticked = TickFlag()
        let tick = Task {
            await model.refreshIfNeeded()
            ticked.isDone = true
        }
        // With the fix the tick waits for the whole inbox too; without it, it would end at once.
        while gated.waitingCount(gate: .inbox(.review)) < 2, !ticked.isDone { await Task.yield() }

        #expect(model.state == .loading)
        gated.open(gate: .inbox(.review))
        await first.value
        await tick.value
        #expect(model.state == .loaded)
        #expect(model.rows.map(\.status) == [.needsReview, .waitingForUpload])
    }

    @Test func aNewerInboxLoadWinsOverAnOlderOne() async throws {
        let old = Self.document(.review, status: .needsReview)
        let fresh = Self.document(.review, status: .needsReview)
        server.onList { _, filter in filter.inboxState == .review ? [old] : [] }
        let gated = GatedDocumentServer(server)
        let model = try model(server: gated)
        await model.load()
        await model.select(.all)
        gated.close(gate: .inbox(.review))

        let older = Task { await model.select(.inbox) }
        while gated.waitingCount(gate: .inbox(.review)) < 1 { await Task.yield() }
        await model.select(.all)
        let newer = Task { await model.select(.inbox) }
        while gated.waitingCount(gate: .inbox(.review)) < 2 { await Task.yield() }

        server.onList { _, filter in filter.inboxState == .review ? [fresh] : [] }
        gated.releaseNewest(gate: .inbox(.review))
        await newer.value
        #expect(model.rows.map(\.id) == [fresh.id])

        // The older load answers last, with what the server had before: it must not win.
        server.onList { _, filter in filter.inboxState == .review ? [old] : [] }
        gated.open(gate: .inbox(.review))
        await older.value
        #expect(model.state == .loaded)
        #expect(model.rows.map(\.id) == [fresh.id])
    }

    @Test func aTickWaitsForAPullToRefreshThatIsRunning() async throws {
        let moving = Self.document(.new, status: .processing)
        let oldReview = Self.document(.review, status: .needsReview)
        server.onList { _, filter in
            switch filter.inboxState {
            case .new: [moving]
            case .review: [oldReview]
            default: []
            }
        }
        let gated = GatedDocumentServer(server)
        let model = try model(server: gated)
        await model.load()
        #expect(model.needsRefresh)
        gated.close(gate: .inbox(.review))
        let atStart = server.calls.count
        let pull = Task { await model.load() }
        // Every other request of the pull is recorded ("new", "unassigned", counts, persons, labels, the counts of
        // "Mijn taken"; the trash is known since the first load, so not asked again); the review list waits at its
        // gate until it opens.
        while !gated.isWaiting(gate: .inbox(.review)) || server.calls.count < atStart + 6 { await Task.yield() }
        #expect(server.calls.count == atStart + 6)
        // Only the held list answers after this change: the others have answered already.
        let freshReview = Self.document(.review, status: .needsReview)
        let secondReview = Self.document(.review, status: .needsReview)
        server.onList { _, filter in
            switch filter.inboxState {
            case .new: [moving]
            case .review: [freshReview, secondReview]
            default: []
            }
        }
        let before = server.calls.count

        await model.refreshIfNeeded()
        #expect(server.calls.count == before)

        gated.open(gate: .inbox(.review))
        await pull.value
        #expect(Set(model.rows.prefix(2).map(\.id)) == [freshReview.id, secondReview.id])
        #expect(model.rows.last?.id == moving.id)
        #expect(model.summary == "Controleren: 2 · Bezig: 1")
    }

    @Test func aScanThatAppearsAndIsReadWithinOneTickStillShowsUp() async throws {
        let moving = Self.document(.new, status: .processing)
        server.onList { _, filter in filter.inboxState == .new ? [moving] : [] }
        let model = try model()
        await model.load()
        // A scan joins the queue just before the tick and is uploaded and read while the tick asks the server.
        let item = FakeUploadQueue.item(workspaceID: workspaceID)
        queue.set([item])
        let arrived = Self.document(.review, status: .needsReview, clientID: item.id)
        let queue = queue
        server.onList { _, filter in
            switch filter.inboxState {
            case .new:
                queue.set([])
                return [moving]
            case .review: return [arrived]
            default: return []
            }
        }

        await model.refreshIfNeeded()

        #expect(model.rows.map(\.id) == [arrived.id, moving.id])
    }
}

@MainActor
private final class TickFlag {
    var isDone = false
}
