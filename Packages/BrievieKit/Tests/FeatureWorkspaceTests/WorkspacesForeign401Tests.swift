@testable import BrievieCore
@testable import FeatureWorkspace
import Foundation
import Testing

/// A 401 without the host's `not_authenticated` (a proxy in front of one address) is a passing error: the next
/// address is tried, and it never counts as a revocation.
@MainActor
@Suite struct WorkspacesForeign401Tests {
    @Test func aForeign401TriesTheNextURLAndIsNoRevocation() async throws {
        let home = try #require(URL(string: "https://brievie.local"))
        let away = try #require(URL(string: "https://brievie.example.nl"))
        let connection = ServerConnection(
            urls: [home, away], caCertificateDER: nil, deviceID: UUID(), userName: "Beheerder"
        )
        let store = ConnectionStore(secrets: InMemorySecretStore())
        try store.save(connection, token: "device-token")
        let appModel = AppModel(
            store: store, authenticator: NoAuthentication(), launchFlag: InMemoryLaunchFlag(hasLaunchedBefore: true),
            isProtectedDataAvailable: { true }
        )
        appModel.didPair(connection)
        let server = WorkspaceServer()
        server.answer = { url in
            if url == home { throw ServerError.other("http_401") }
            return []
        }
        let model = WorkspacesModel(
            connection: connection, store: store, server: server, appModel: appModel,
            unpairing: Unpairing(server: server, uploads: ScriptedUploadQueue(count: 0))
        )

        await model.load()

        #expect(server.urls == [home, away])
        #expect(model.state == .loaded([]))
        #expect(appModel.state == .ready(connection))
    }
}
