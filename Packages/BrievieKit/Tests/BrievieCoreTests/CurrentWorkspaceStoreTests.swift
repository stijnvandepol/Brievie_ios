@testable import BrievieCore
import Foundation
import Testing

/// The workspace the inbox shows, remembered per pairing in `UserDefaults`, and forgotten with the pairing.
@Suite struct CurrentWorkspaceStoreTests {
    private let suiteName = "current-workspace-\(UUID().uuidString)"

    @Test func nothingIsRememberedAtFirst() {
        let store = UserDefaultsCurrentWorkspaceStore(suiteName: suiteName)

        #expect(store.workspace(forDevice: UUID()) == nil)
    }

    @Test func theChoiceIsKeptPerPairing() {
        let store = UserDefaultsCurrentWorkspaceStore(suiteName: suiteName)
        let device = UUID()
        let workspace = UUID()

        store.remember(workspace, forDevice: device)

        #expect(store.workspace(forDevice: device) == workspace)
        #expect(UserDefaultsCurrentWorkspaceStore(suiteName: suiteName).workspace(forDevice: device) == workspace)
        #expect(UserDefaults(suiteName: suiteName)?.string(forKey: "currentWorkspace.\(device.uuidString)")
            == workspace.uuidString)
    }

    @Test func anotherPairingDoesNotReuseTheChoice() {
        let store = UserDefaultsCurrentWorkspaceStore(suiteName: suiteName)
        store.remember(UUID(), forDevice: UUID())

        #expect(store.workspace(forDevice: UUID()) == nil)
    }

    @Test func rememberingAgainReplacesTheChoice() {
        let store = UserDefaultsCurrentWorkspaceStore(suiteName: suiteName)
        let device = UUID()
        let business = UUID()
        store.remember(UUID(), forDevice: device)

        store.remember(business, forDevice: device)

        #expect(store.workspace(forDevice: device) == business)
    }

    @Test func removeAllForgetsEveryChoiceAndNothingElse() {
        let store = UserDefaultsCurrentWorkspaceStore(suiteName: suiteName)
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.set(true, forKey: "hasLaunchedBefore")
        defaults?.set("calendar-1", forKey: "calendar.\(UUID().uuidString)")
        let first = UUID()
        let second = UUID()
        store.remember(UUID(), forDevice: first)
        store.remember(UUID(), forDevice: second)

        store.removeAll()

        #expect(store.workspace(forDevice: first) == nil)
        #expect(store.workspace(forDevice: second) == nil)
        #expect(defaults?.bool(forKey: "hasLaunchedBefore") == true)
        #expect(defaults?.dictionaryRepresentation().keys.contains { $0.hasPrefix("calendar.") } == true)
    }

    @Test func aValueThatIsNotAUUIDReadsAsNothing() {
        let store = UserDefaultsCurrentWorkspaceStore(suiteName: suiteName)
        let device = UUID()
        UserDefaults(suiteName: suiteName)?.set("not-a-uuid", forKey: "currentWorkspace.\(device.uuidString)")

        #expect(store.workspace(forDevice: device) == nil)
    }

    @Test func theInMemoryStoreBehavesTheSame() {
        let store = InMemoryCurrentWorkspaceStore()
        let device = UUID()
        let workspace = UUID()

        store.remember(workspace, forDevice: device)
        #expect(store.workspace(forDevice: device) == workspace)
        #expect(store.workspace(forDevice: UUID()) == nil)

        store.removeAll()
        #expect(store.workspace(forDevice: device) == nil)
    }
}

/// Forgetting the pairing ("Ontkoppelen" or a revocation) forgets which workspace the inbox showed.
@MainActor
@Suite struct AppModelCurrentWorkspaceTests {
    private let secrets = InMemorySecretStore()
    private var store: ConnectionStore { ConnectionStore(secrets: secrets) }
    private let current = InMemoryCurrentWorkspaceStore()
    private let connection: ServerConnection

    init() throws {
        let url = try #require(URL(string: "https://brievie.local"))
        connection = ServerConnection(urls: [url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn")
        try ConnectionStore(secrets: secrets).save(connection, token: "device-token")
    }

    private func readyModel() async -> AppModel {
        let model = AppModel(
            store: store, authenticator: FakeAuthenticator(), launchFlag: InMemoryLaunchFlag(hasLaunchedBefore: true),
            isProtectedDataAvailable: { true }, currentWorkspace: current
        )
        model.start()
        await model.unlock()
        current.remember(UUID(), forDevice: connection.deviceID)
        return model
    }

    @Test func unpairingForgetsTheCurrentWorkspace() async throws {
        let model = await readyModel()

        let unpaired = await model.unpair(Unpairing(server: try FakeBrievieServer(), uploads: EmptyUploadQueue()))

        #expect(unpaired)
        #expect(current.workspace(forDevice: connection.deviceID) == nil)
    }

    @Test func aRevocationForgetsTheCurrentWorkspace() async {
        let model = await readyModel()

        model.sessionRevoked(deviceID: connection.deviceID)

        #expect(model.state == .unpaired(notice: AppStrings.sessionRevoked))
        #expect(current.workspace(forDevice: connection.deviceID) == nil)
    }

    @Test func aStaleRevocationKeepsTheCurrentWorkspace() async {
        let model = await readyModel()

        model.sessionRevoked(deviceID: UUID())

        #expect(current.workspace(forDevice: connection.deviceID) != nil)
    }
}
