import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

@MainActor
@Suite struct DocumentsModelTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")

    private let workspaceID = UUID()
    private let store = ConnectionStore(secrets: InMemorySecretStore())
    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
    private let queue = FakeUploadQueue()
    private let events = EventLog()

    private func model(canScan: Bool = true) throws -> DocumentsModel {
        let connection = ServerConnection(
            urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn"
        )
        try store.save(connection, token: "tok")
        return DocumentsModel(
            documents: WorkspaceDocuments(
                workspaceID: workspaceID, connection: connection, store: store, server: server
            ),
            uploads: queue,
            canScan: canScan,
            onRevoked: { [events] in events.add("revoked") },
            onMissingPairing: { [events] in events.add("missing") }
        )
    }

    @Test func serverDocumentsBecomeRowsNewestFirst() async throws {
        let older = DocumentFixtures.summary(status: .done, sender: "CAK", createdAt: Date(timeIntervalSince1970: 100))
        let newer = DocumentFixtures.summary(status: .needsReview, createdAt: Date(timeIntervalSince1970: 200))
        server.onList { _ in [older, newer] }
        let model = try model()

        await model.load()

        #expect(model.state == .loaded)
        #expect(model.rows.map(\.id) == [newer.id, older.id])
        #expect(model.rows.map(\.status) == [.needsReview, .done])
        #expect(model.rows.map(\.title) == [DocumentStrings.newDocument, "CAK"])
        #expect(model.rows.map(\.documentID) == [newer.id, older.id])
    }

    @Test func queuedScanAndItsServerDocumentAreOneRow() async throws {
        let item = FakeUploadQueue.item(workspaceID: workspaceID, state: .uploading)
        let other = FakeUploadQueue.item(workspaceID: workspaceID, state: .waiting)
        let elsewhere = FakeUploadQueue.item(workspaceID: UUID())
        queue.set([item, other, elsewhere])
        let arrived = DocumentFixtures.summary(clientID: item.id, status: .processing)
        server.onList { _ in [arrived] }
        let model = try model()

        await model.load()

        #expect(model.rows.map(\.id) == [other.id, arrived.id])
        #expect(model.rows.map(\.status) == [.waitingForUpload, .processing])
        #expect(model.rows.first?.documentID == nil)
    }

    @Test func uploadProgressShowsOnTheRow() async throws {
        let item = FakeUploadQueue.item(workspaceID: workspaceID, state: .uploading)
        queue.set([item])
        let model = try model()
        await model.load()
        // Nothing sent yet (offline, or scheduled for later): it waits, and can still be taken back.
        #expect(model.rows.map(\.status) == [.waitingForUpload])
        #expect(model.rows.first?.status.canDelete == true)

        let observing = Task { await model.observeProgress() }
        await Task.yield()
        while await queue.progressSubscriberCount == 0 { await Task.yield() }
        queue.sendProgress([item.id: 0.4])
        queue.finishProgress()
        await observing.value

        #expect(model.rows.map(\.status) == [.uploading(progress: 0.4)])
    }

    @Test(arguments: [
        ("untrusted", DocumentStrings.notVerified),
        ("workspace_not_found", DocumentStrings.workspaceGone),
        ("server_changed", DocumentStrings.otherServer),
        ("payload_too_large", DocumentStrings.tooLarge),
        ("document_conflict", DocumentStrings.uploadFailed),
        ("http_500", DocumentStrings.uploadFailed)
    ])
    func failedUploadExplainsItselfInDutch(code: String, message: String) async throws {
        queue.set([FakeUploadQueue.item(workspaceID: workspaceID, state: .failed, failureCode: code)])
        let model = try model()

        await model.load()

        let canRetry = code != "server_changed"
        #expect(model.rows.map(\.status) == [.uploadFailed(message: message, canRetry: canRetry)])
    }

    @Test func scanOnItsWayCanStillBeDeleted() {
        // Final review: a private letter scanned into the wrong workspace must be stoppable.
        #expect(DocumentsModel.RowStatus.uploading(progress: 0.4).canDelete)
        #expect(DocumentsModel.RowStatus.waitingForUpload.canDelete)
        #expect(!DocumentsModel.RowStatus.processing.canDelete)
        #expect(!DocumentsModel.RowStatus.uploading(progress: 0.4).canRetryUpload)
    }

    @Test func scanForAnotherServerCanOnlyBeDeleted() async throws {
        queue.set([FakeUploadQueue.item(workspaceID: workspaceID, state: .failed, failureCode: "server_changed")])
        let model = try model()

        await model.load()

        #expect(model.rows.first?.status.canDelete == true)
        #expect(model.rows.first?.status.canRetryUpload == false)
    }

    @Test func retryAndDeleteGoToTheQueue() async throws {
        let item = FakeUploadQueue.item(workspaceID: workspaceID, state: .failed, failureCode: "http_500")
        queue.set([item])
        let model = try model()
        await model.load()

        await model.retryUpload(item.id)
        await model.deleteUpload(item.id)

        #expect(queue.retried == [item.id])
        #expect(queue.deleted == [item.id])
        #expect(model.rows.isEmpty)
    }

    @Test func refreshIsNeededOnlyWhileSomethingIsMoving() async throws {
        let moving = DocumentFixtures.summary(status: .processing)
        server.onList { _ in [moving] }
        let model = try model()
        await model.load()
        #expect(model.needsRefresh)

        server.onList { _ in [DocumentFixtures.summary(id: moving.id, status: .needsReview)] }
        await model.refreshIfNeeded()

        #expect(model.rows.map(\.status) == [.needsReview])
        #expect(!model.needsRefresh)
        let calls = server.calls.count
        await model.refreshIfNeeded()
        #expect(server.calls.count == calls)
    }

    @Test func revokedDeviceEndsTheSession() async throws {
        server.onList { _ in throw ServerError.unauthorized }
        let model = try model()

        await model.load()

        #expect(events.all == ["revoked"])
    }

    @Test func missingPairingEndsTheSession() async throws {
        let model = try model()
        try store.clear()

        await model.load()

        #expect(events.all == ["missing"])
    }

    @Test func firstLoadFailureShowsAMessageButQueuedScansStayVisible() async throws {
        let item = FakeUploadQueue.item(workspaceID: workspaceID)
        queue.set([item])
        server.onList { _ in throw ServerError.unreachable }
        let model = try model()

        await model.load()

        #expect(model.state == .failed(message: DocumentStrings.unreachable))
        #expect(model.rows.map(\.id) == [item.id])
    }

    @Test func laterFailureKeepsTheListOnScreen() async throws {
        let document = DocumentFixtures.summary(status: .done)
        server.onList { _ in [document] }
        let model = try model()
        await model.load()
        server.onList { _ in throw ServerError.unreachable }

        await model.load()

        #expect(model.state == .loaded)
        #expect(model.rows.map(\.id) == [document.id])
    }

    @Test func viewerCannotScan() throws {
        #expect(try model(canScan: false).canScan == false)
        #expect(try model().canScan)
    }

    @Test func subtitleNamesTheDateAndThePages() async throws {
        let one = FakeUploadQueue.item(workspaceID: workspaceID, pageCount: 1)
        let three = FakeUploadQueue.item(
            workspaceID: workspaceID, pageCount: 3, createdAt: Date(timeIntervalSince1970: 1_794_650_500)
        )
        queue.set([one, three])
        let model = try model()

        await model.load()

        #expect(model.rows.map(\.subtitle) == ["14 nov 2026 · 3 pagina's", "14 nov 2026 · 1 pagina"])
    }

    @Test func catalogAndCodeAgree() throws {
        for (key, resolved) in DocumentStrings.all {
            #expect(try CatalogParity.dutchValue(forKey: key, target: "FeatureDocuments") == resolved, "\(key)")
        }
    }
}

/// Collects what the model reported to the app.
final class EventLog: Sendable {
    private let events = LockedList()

    func add(_ event: String) { events.append(event) }
    var all: [String] { events.values }
}
