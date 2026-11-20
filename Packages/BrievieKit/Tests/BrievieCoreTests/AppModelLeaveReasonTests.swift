@testable import BrievieCore
import Foundation
import Testing

/// Why the app left the paired state travels with that transition: a screen that is still alive and reads the
/// storage the transition emptied never replaces the reason (seen in the simulator, 20-11-2026: "Er ging iets mis"
/// after a revocation and after "Ontkoppelen").
@MainActor
@Suite struct AppModelLeaveReasonTests {
    private let secrets = InMemorySecretStore()
    private var store: ConnectionStore { ConnectionStore(secrets: secrets) }
    private let server: FakeBrievieServer
    private let connection: ServerConnection
    private let documents = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }

    init() throws {
        server = try FakeBrievieServer()
        connection = ServerConnection(
            urls: [try #require(URL(string: "https://brievie.example.nl"))], caCertificateDER: nil,
            deviceID: UUID(), userName: "Beheerder"
        )
        try ConnectionStore(secrets: secrets).save(connection, token: "device-token")
    }

    private func readyModel() async -> AppModel {
        let model = AppModel(
            store: store, authenticator: FakeAuthenticator(),
            launchFlag: InMemoryLaunchFlag(hasLaunchedBefore: true), isProtectedDataAvailable: { true }
        )
        model.start()
        await model.unlock()
        return model
    }

    /// A post screen of this pairing, wired as the app wires it: a 401 ends the session from the call itself.
    private func postScreen(of model: AppModel) -> WorkspaceDocuments {
        WorkspaceDocuments(
            workspaceID: UUID(), connection: connection, store: store, server: documents,
            onRevoked: { deviceID in await model.sessionRevoked(deviceID: deviceID) }
        )
    }

    @Test func aRevocationKeepsItsNoticeWhenAScreenThenFindsTheStorageEmpty() async throws {
        let model = await readyModel()
        documents.onList { _ in throw ServerError.unauthorized }

        await #expect(throws: DocumentsError.revoked) { try await postScreen(of: model).list() }
        #expect(model.state == .unpaired(notice: AppStrings.sessionRevoked))

        // The review's other calls of the same moment read the emptied storage.
        await #expect(throws: DocumentsError.missingPairing) { try await postScreen(of: model).persons() }
        model.connectionMissing()

        #expect(model.state == .unpaired(notice: AppStrings.sessionRevoked))
    }

    @Test func anExpiredTokenEndsTheSameWay() async throws {
        let model = await readyModel()
        // The host answers an expired token like a revoked one; the live mapping is pinned in `ExpiredTokenTests`.
        documents.onOpenTasks { _ in throw ServerError(status: 401, code: "not_authenticated") }

        await #expect(throws: DocumentsError.revoked) { try await postScreen(of: model).openTasks() }
        model.connectionMissing()
        model.sessionRevoked(deviceID: connection.deviceID)

        #expect(model.state == .unpaired(notice: AppStrings.sessionRevoked))
    }

    @Test func unpairingShowsNoNoticeAlsoWhenAScreenThenFindsTheStorageEmpty() async throws {
        let model = await readyModel()
        let uploads = UploadCoordinator(
            store: UploadQueueStore(
                directory: FileManager.default.temporaryDirectory.appending(path: "leave-\(UUID().uuidString)")
            ),
            transport: FakeUploadTransport(), connection: { nil }, onRevoked: { _ in }
        )

        #expect(await model.unpair(Unpairing(server: server, uploads: uploads)))
        #expect(model.state == .unpaired(notice: nil))

        // A screen still alive reads the empty storage; a late 401 of a call that was under way arrives.
        model.connectionMissing()
        model.sessionRevoked(deviceID: connection.deviceID)

        #expect(model.state == .unpaired(notice: nil))
    }

    @Test func storageThatIsUnexpectedlyEmptyKeepsTheGenericNotice() async throws {
        let model = await readyModel()
        try store.clear()

        model.connectionMissing()

        #expect(model.state == .unpaired(notice: AppStrings.genericError))
    }

    @Test func aRevocationReportedTwiceForgetsOnce() async throws {
        let model = await readyModel()

        model.sessionRevoked(deviceID: connection.deviceID)
        model.sessionRevoked(deviceID: connection.deviceID)

        #expect(model.state == .unpaired(notice: AppStrings.sessionRevoked))
        #expect(try store.load() == nil)
    }
}
