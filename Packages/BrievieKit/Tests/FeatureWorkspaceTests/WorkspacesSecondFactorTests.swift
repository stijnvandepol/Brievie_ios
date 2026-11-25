@testable import BrievieCore
@testable import FeatureWorkspace
import Foundation
import Testing

/// The host blocks a device token (401 `second_factor_required`) while the account must set up two-step
/// verification first. The phone stays paired, says what to do, and tries again when the user comes back.
@MainActor
@Suite struct WorkspacesSecondFactorTests {
    @Test func secondFactorRequiredKeepsThePairingAndRetriesWhenTheAppIsActiveAgain() async throws {
        let home = try #require(URL(string: "https://brievie.local"))
        let connection = ServerConnection(urls: [home], caCertificateDER: nil, deviceID: UUID(), userName: "Lid")
        let store = ConnectionStore(secrets: InMemorySecretStore())
        try store.save(connection, token: "device-token")
        let appModel = AppModel(
            store: store, authenticator: NoAuthentication(), launchFlag: InMemoryLaunchFlag(hasLaunchedBefore: true),
            isProtectedDataAvailable: { true }
        )
        appModel.didPair(connection)
        let server = WorkspaceServer()
        server.answer = { _ in throw ServerError.other("second_factor_required") }
        let model = WorkspacesModel(
            connection: connection, store: store, server: server, appModel: appModel,
            unpairing: Unpairing(server: server, uploads: ScriptedUploadQueue(count: 0))
        )

        await model.load()

        #expect(model.state == .failed(message: WorkspaceStrings.secondFactorRequired))
        #expect(appModel.state == .ready(connection))
        #expect(try store.load() != nil)

        server.answer = { _ in [] }
        await model.sceneBecameActive()

        #expect(model.state == .loaded([]))
        #expect(server.urls == [home, home])
    }
}
