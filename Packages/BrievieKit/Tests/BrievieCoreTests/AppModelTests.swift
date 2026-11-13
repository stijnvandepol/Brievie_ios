@testable import BrievieCore
import Foundation
import Synchronization
import Testing

/// An authenticator whose answers are set per test. `onAuthenticate` runs while the prompt is "on screen".
final class FakeAuthenticator: DeviceAuthenticator {
    private struct State {
        var canAuthenticate = true
        var succeeds = true
        var prompts = 0
        var reasons: [String] = []
    }

    private let state = Mutex(State())
    private let onAuthenticate: @Sendable () async -> Void

    init(onAuthenticate: @escaping @Sendable () async -> Void = {}) {
        self.onAuthenticate = onAuthenticate
    }

    var canAuthenticateValue: Bool {
        get { state.withLock { $0.canAuthenticate } }
        set { state.withLock { $0.canAuthenticate = newValue } }
    }

    var succeeds: Bool {
        get { state.withLock { $0.succeeds } }
        set { state.withLock { $0.succeeds = newValue } }
    }

    var prompts: Int { state.withLock { $0.prompts } }
    var reasons: [String] { state.withLock { $0.reasons } }

    func canAuthenticate() -> Bool {
        state.withLock { $0.canAuthenticate }
    }

    func authenticate(reason: String) async -> Bool {
        state.withLock {
            $0.prompts += 1
            $0.reasons.append(reason)
        }
        await onAuthenticate()
        return state.withLock { $0.succeeds }
    }
}

@MainActor
@Suite struct AppModelTests {
    private let secrets = InMemorySecretStore()
    private var store: ConnectionStore { ConnectionStore(secrets: secrets) }

    private func connection() throws -> ServerConnection {
        ServerConnection(
            urls: [try #require(URL(string: "https://brievie.local"))],
            caCertificateDER: nil,
            deviceID: UUID(),
            userName: "Beheerder"
        )
    }

    private func pairedStore() throws -> ServerConnection {
        let connection = try connection()
        try store.save(connection, token: "device-token")
        return connection
    }

    // MARK: - start

    @Test func startIsUnpairedWithAnEmptyStore() {
        let model = AppModel(store: store, authenticator: FakeAuthenticator())

        model.start()

        #expect(model.state == .unpaired(notice: nil))
    }

    @Test func startIsLockedWithAStoredConnection() throws {
        _ = try pairedStore()
        let model = AppModel(store: store, authenticator: FakeAuthenticator())

        model.start()

        #expect(model.state == .locked)
    }

    // MARK: - unlock

    @Test func unlockSuccessOpensTheApp() async throws {
        let connection = try pairedStore()
        let authenticator = FakeAuthenticator()
        let model = AppModel(store: store, authenticator: authenticator)
        model.start()

        await model.unlock()

        #expect(model.state == .ready(connection))
        #expect(!model.showsNoPasscodeWarning)
        #expect(authenticator.reasons == ["Ontgrendel Brievie om je post te zien."])
    }

    @Test func unlockFailureStaysLocked() async throws {
        _ = try pairedStore()
        let authenticator = FakeAuthenticator()
        authenticator.succeeds = false
        let model = AppModel(store: store, authenticator: authenticator)
        model.start()

        await model.unlock()

        #expect(model.state == .locked)
    }

    // MARK: - Review Focus 5: no passcode

    @Test func withoutAPasscodeTheAppOpensWithAWarning() async throws {
        let connection = try pairedStore()
        let authenticator = FakeAuthenticator()
        authenticator.canAuthenticateValue = false
        let model = AppModel(store: store, authenticator: authenticator)
        model.start()

        await model.unlock()

        #expect(model.state == .ready(connection))
        #expect(model.showsNoPasscodeWarning)
        #expect(authenticator.prompts == 0)
    }

    @Test func theWarningGoesAwayOnceTheDeviceHasAPasscode() async throws {
        _ = try pairedStore()
        let authenticator = FakeAuthenticator()
        authenticator.canAuthenticateValue = false
        let model = AppModel(store: store, authenticator: authenticator)
        model.start()
        await model.unlock()
        model.didEnterBackground()
        authenticator.canAuthenticateValue = true

        await model.unlock()

        #expect(!model.showsNoPasscodeWarning)
    }

    @Test func pairingOnADeviceWithoutPasscodeShowsTheWarning() throws {
        let authenticator = FakeAuthenticator()
        authenticator.canAuthenticateValue = false
        let model = AppModel(store: store, authenticator: authenticator)
        model.start()

        model.didPair(try connection())

        #expect(model.showsNoPasscodeWarning)
    }

    // MARK: - locking

    @Test func pairingOpensTheAppWithoutAPrompt() throws {
        let authenticator = FakeAuthenticator()
        let model = AppModel(store: store, authenticator: authenticator)
        model.start()
        let connection = try connection()

        model.didPair(connection)

        #expect(model.state == .ready(connection))
        #expect(authenticator.prompts == 0)
    }

    @Test func goingToTheBackgroundLocksTheApp() async throws {
        _ = try pairedStore()
        let model = AppModel(store: store, authenticator: FakeAuthenticator())
        model.start()
        await model.unlock()

        model.didEnterBackground()

        #expect(model.state == .locked)
    }

    @Test func backgroundDoesNotLockAnUnpairedApp() {
        let model = AppModel(store: store, authenticator: FakeAuthenticator())
        model.start()

        model.didEnterBackground()

        #expect(model.state == .unpaired(notice: nil))
    }

    @Test func unlockingDoesNotLockTheAppAgain() async throws {
        // Face ID's own sheet makes the scene inactive but never backgrounds it: nothing but the
        // background callback may lock, so a finished unlock stays unlocked.
        let connection = try pairedStore()
        let model = AppModel(store: store, authenticator: FakeAuthenticator())
        model.start()

        await model.didBecomeActive()
        await model.didBecomeActive()

        #expect(model.state == .ready(connection))
    }

    @Test func backgroundDuringThePromptDiscardsTheResult() async throws {
        _ = try pairedStore()
        let box = ModelBox()
        let authenticator = FakeAuthenticator { await box.model?.didEnterBackground() }
        let model = AppModel(store: store, authenticator: authenticator)
        box.model = model
        model.start()

        await model.unlock()

        #expect(model.state == .locked)
    }

    @Test func activationPromptsOncePerLaunchOrBackground() async throws {
        _ = try pairedStore()
        let authenticator = FakeAuthenticator()
        authenticator.succeeds = false
        let model = AppModel(store: store, authenticator: authenticator)
        model.start()

        await model.didBecomeActive()
        // The user cancelled the prompt; the sheet closing makes the app active again. No second prompt.
        await model.didBecomeActive()
        #expect(authenticator.prompts == 1)

        model.didEnterBackground()
        await model.didBecomeActive()
        #expect(authenticator.prompts == 2)
    }

    @Test func twoUnlocksAtOnceShowOnePrompt() async throws {
        _ = try pairedStore()
        let authenticator = FakeAuthenticator { await Task.yield() }
        let model = AppModel(store: store, authenticator: authenticator)
        model.start()

        async let first: Void = model.unlock()
        async let second: Void = model.unlock()
        _ = await (first, second)

        #expect(authenticator.prompts == 1)
    }

    // MARK: - Review Focus 6: revoked

    @Test func sessionRevokedClearsTheStoreAndExplains() async throws {
        _ = try pairedStore()
        let model = AppModel(store: store, authenticator: FakeAuthenticator())
        model.start()
        await model.unlock()

        model.sessionRevoked()

        #expect(model.state == .unpaired(
            notice: "Dit apparaat is ontkoppeld. Koppel het opnieuw om verder te gaan."
        ))
        #expect(try store.load() == nil)
        #expect(secrets.read(.deviceToken) == nil)
        #expect(secrets.read(.serverConnection) == nil)
    }

    @Test func pairingAfterARevocationLeavesTheNoticeBehind() throws {
        _ = try pairedStore()
        let model = AppModel(store: store, authenticator: FakeAuthenticator())
        model.start()
        model.sessionRevoked()
        let connection = try connection()

        model.didPair(connection)

        #expect(model.state == .ready(connection))
    }

    @Test func aStoreThatCannotBeReadKeepsTheAppLockedInsteadOfUnpairing() {
        let model = AppModel(store: ConnectionStore(secrets: UnreadableStore()), authenticator: FakeAuthenticator())

        model.start()

        #expect(model.state == .locked)
    }
}

@MainActor
private final class ModelBox {
    var model: AppModel?
}

private struct UnreadableStore: SecretStore {
    struct Unreadable: Error {}

    func read(_ key: SecretKey) throws -> Data? { throw Unreadable() }
    func write(_ data: Data, for key: SecretKey) throws {}
    func delete(_ key: SecretKey) throws {}
}
