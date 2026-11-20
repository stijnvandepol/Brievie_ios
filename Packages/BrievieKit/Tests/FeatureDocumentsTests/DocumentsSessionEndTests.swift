import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// A 401 `not_authenticated` on any call of the post ends the session at once, also on a refresh of a list that is
/// already on screen and on a call whose failure the screen otherwise ignores (persons, labels, counts). The call
/// itself reports it (`WorkspaceDocuments`' hook); the screen's own callback is the second, idempotent report.
@MainActor
@Suite struct DocumentsSessionEndTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")

    private let store = ConnectionStore(secrets: InMemorySecretStore())
    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
    private let queue = FakeUploadQueue()
    /// What the hook in `WorkspaceDocuments` reported (the app's `AppModel.sessionRevoked`).
    private let ended = LockedList()
    private let events = EventLog()
    private let connection = ServerConnection(
        urls: [DocumentsSessionEndTests.url], caCertificateDER: nil, deviceID: UUID(), userName: "Jesse"
    )

    private func model() throws -> DocumentsModel {
        try store.save(connection, token: "tok")
        return DocumentsModel(
            documents: WorkspaceDocuments(
                workspaceID: UUID(), connection: connection, store: store, server: server,
                onRevoked: { [ended] id in ended.append(id.uuidString) }
            ),
            uploads: queue, canScan: true, camera: FakeScanCamera(.allowed), openSettings: {},
            onRevoked: { [events] in events.add("revoked") },
            onMissingPairing: { [events] in events.add("missing") }
        )
    }

    @Test func pullToRefreshOnAListAlreadyOnScreenEndsTheSession() async throws {
        server.onList { _ in [DocumentFixtures.summary(status: .needsReview, inboxState: .review)] }
        let model = try model()
        await model.load()
        #expect(model.rows.count == 1)

        server.onList { _ in throw ServerError.unauthorized }
        await model.load()

        #expect(ended.values.contains(connection.deviceID.uuidString))
        #expect(events.all.contains("revoked"))
    }

    @Test func theAutomaticRefreshEndsTheSessionToo() async throws {
        server.onList { _ in [DocumentFixtures.summary(status: .processing, inboxState: .new)] }
        let model = try model()
        await model.load()

        server.onList { _ in throw ServerError.unauthorized }
        await model.refreshIfNeeded()

        #expect(ended.values.contains(connection.deviceID.uuidString))
    }

    @Test func aRefusedPersonsListEndsTheSessionAlthoughTheListLoads() async throws {
        server.onList { _ in [DocumentFixtures.summary(status: .needsReview, inboxState: .review)] }
        server.onPersons { _ in throw ServerError.unauthorized }
        let model = try model()

        await model.load()

        #expect(ended.values == [connection.deviceID.uuidString])
    }

    @Test func refusedCountsEndTheSession() async throws {
        server.onInboxCounts { _ in throw ServerError.unauthorized }
        let model = try model()

        await model.load()

        #expect(ended.values == [connection.deviceID.uuidString])
    }

    @Test func aForeign401EndsNothing() async throws {
        server.onList { _ in throw ServerError.other("http_401") }
        let model = try model()

        await model.load()

        #expect(ended.values.isEmpty)
        #expect(events.all.isEmpty)
    }
}
