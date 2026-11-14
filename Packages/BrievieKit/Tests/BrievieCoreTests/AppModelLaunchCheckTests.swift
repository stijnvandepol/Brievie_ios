@testable import BrievieCore
import Foundation
import Testing

/// The first-launch check: a pairing left behind by a previous install is cleared, never unlocked.
@MainActor
@Suite struct AppModelLaunchCheckTests {
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

    private func makeModel(
        _ authenticator: FakeAuthenticator = FakeAuthenticator(),
        store: ConnectionStore? = nil,
        launchFlag: any LaunchFlag = InMemoryLaunchFlag(hasLaunchedBefore: true),
        protectedDataAvailable: Bool = true
    ) -> AppModel {
        AppModel(
            store: store ?? self.store,
            authenticator: authenticator,
            launchFlag: launchFlag,
            isProtectedDataAvailable: { protectedDataAvailable }
        )
    }

    @Test func startNeverClearsAnything() throws {
        // `start()` runs from App.init, possibly in a prewarm before the first unlock: the flag may read false.
        _ = try pairedStore()
        let flag = InMemoryLaunchFlag(hasLaunchedBefore: false)
        let model = makeModel(launchFlag: flag)

        model.start()

        #expect(model.state == .locked)
        #expect(secrets.read(.deviceToken) != nil)
        #expect(!flag.hasLaunchedBefore)
    }

    @Test func theFirstActivationOfAFreshInstallClearsLeftoversAndUnpairs() async throws {
        _ = try pairedStore()
        let flag = InMemoryLaunchFlag(hasLaunchedBefore: false)
        let authenticator = FakeAuthenticator()
        let model = makeModel(authenticator, launchFlag: flag)
        model.start()

        await model.didBecomeActive()

        #expect(model.state == .unpaired(notice: nil))
        #expect(secrets.read(.deviceToken) == nil)
        #expect(secrets.read(.serverConnection) == nil)
        #expect(flag.hasLaunchedBefore)
        #expect(authenticator.prompts == 0)
    }

    @Test func theFirstActivationWithTheFlagPresentKeepsThePairing() async throws {
        let connection = try pairedStore()
        let model = makeModel(launchFlag: InMemoryLaunchFlag(hasLaunchedBefore: true))
        model.start()

        await model.didBecomeActive()

        #expect(model.state == .ready(connection))
        #expect(try store.load()?.connection == connection)
    }

    @Test func withoutProtectedDataALeftoverIsNeitherClearedNorUnlocked() async throws {
        _ = try pairedStore()
        let flag = InMemoryLaunchFlag(hasLaunchedBefore: false)
        let authenticator = FakeAuthenticator()
        var available = false
        let model = AppModel(
            store: store,
            authenticator: authenticator,
            launchFlag: flag,
            isProtectedDataAvailable: { available }
        )
        model.start()

        await model.didBecomeActive()

        #expect(model.state == .locked)
        #expect(authenticator.prompts == 0)
        #expect(secrets.read(.deviceToken) != nil)
        #expect(!flag.hasLaunchedBefore)

        available = true
        model.didEnterBackground()
        await model.didBecomeActive()

        #expect(model.state == .unpaired(notice: nil))
        #expect(secrets.read(.deviceToken) == nil)
        #expect(secrets.read(.serverConnection) == nil)
        #expect(flag.hasLaunchedBefore)
        #expect(authenticator.prompts == 0)
    }

    @Test func withoutProtectedDataTheUnlockButtonDoesNotOpenALeftover() async throws {
        _ = try pairedStore()
        let authenticator = FakeAuthenticator()
        let model = makeModel(
            authenticator,
            launchFlag: InMemoryLaunchFlag(hasLaunchedBefore: false),
            protectedDataAvailable: false
        )
        model.start()
        await model.didBecomeActive()

        model.requestUnlock()
        await model.pendingTask?.value

        #expect(model.state == .locked)
        #expect(authenticator.prompts == 0)
        #expect(secrets.read(.deviceToken) != nil)
    }

    @Test func withoutProtectedDataAndWithoutPasscodeALeftoverStaysLocked() async throws {
        // No passcode means no prompt: the gate itself must keep the leftover closed.
        _ = try pairedStore()
        let authenticator = FakeAuthenticator()
        authenticator.availabilityValue = .noPasscode
        let model = makeModel(
            authenticator,
            launchFlag: InMemoryLaunchFlag(hasLaunchedBefore: false),
            protectedDataAvailable: false
        )
        model.start()

        await model.didBecomeActive()
        await model.unlock()

        #expect(model.state == .locked)
        #expect(secrets.read(.deviceToken) != nil)
    }

    @Test func protectedDataBecomingAvailableRunsTheCheck() async throws {
        _ = try pairedStore()
        let flag = InMemoryLaunchFlag(hasLaunchedBefore: false)
        let authenticator = FakeAuthenticator()
        var available = false
        let model = AppModel(
            store: store,
            authenticator: authenticator,
            launchFlag: flag,
            isProtectedDataAvailable: { available }
        )
        model.start()
        await model.didBecomeActive()

        available = true
        model.protectedDataDidBecomeAvailable()
        await model.pendingTask?.value

        #expect(model.state == .unpaired(notice: nil))
        #expect(secrets.read(.deviceToken) == nil)
        #expect(flag.hasLaunchedBefore)
        #expect(authenticator.prompts == 0)
    }

    @Test func protectedDataBecomingAvailableOnAnExistingInstallUnlocks() async throws {
        let connection = try pairedStore()
        let authenticator = FakeAuthenticator()
        var available = false
        let model = AppModel(
            store: store,
            authenticator: authenticator,
            launchFlag: InMemoryLaunchFlag(hasLaunchedBefore: true),
            isProtectedDataAvailable: { available }
        )
        model.start()
        await model.didBecomeActive()
        #expect(model.state == .locked)

        available = true
        model.protectedDataDidBecomeAvailable()
        await model.pendingTask?.value

        #expect(model.state == .ready(connection))
        #expect(authenticator.prompts == 1)
    }

    @Test func aFailedClearKeepsALeftoverLockedUntilAClearSucceeds() async throws {
        let flaky = FlakyDeleteStore()
        let flakyStore = ConnectionStore(secrets: flaky)
        try flakyStore.save(try connection(), token: "device-token")
        flaky.deleteFails = true
        let flag = InMemoryLaunchFlag(hasLaunchedBefore: false)
        let authenticator = FakeAuthenticator()
        let model = makeModel(authenticator, store: flakyStore, launchFlag: flag)
        model.start()

        await model.didBecomeActive()
        await model.unlock()

        #expect(model.state == .locked)
        #expect(!flag.hasLaunchedBefore)
        #expect(authenticator.prompts == 0)

        flaky.deleteFails = false
        model.didEnterBackground()
        await model.didBecomeActive()

        #expect(model.state == .unpaired(notice: nil))
        #expect(try flakyStore.load() == nil)
        #expect(flag.hasLaunchedBefore)
        #expect(authenticator.prompts == 0)
    }

    @Test func theCheckRunsOncePerProcess() async throws {
        // Once the check passed, a flag that later reads `false` (for example unreadable defaults) must not
        // wipe the pairing that is in use.
        let connection = try pairedStore()
        let flag = ScriptedLaunchFlag(hasLaunchedBefore: true)
        let model = AppModel(
            store: store,
            authenticator: FakeAuthenticator(),
            launchFlag: flag,
            isProtectedDataAvailable: { true }
        )
        model.start()
        await model.didBecomeActive()
        #expect(model.state == .ready(connection))
        flag.hasLaunchedBefore = false
        model.didEnterBackground()

        await model.didBecomeActive()

        #expect(model.state == .ready(connection))
        #expect(try store.load()?.connection == connection)
    }

    @Test func aPairingMadeBeforeTheCheckCouldRunIsNotCleared() async throws {
        // Protected data was unavailable at the first activation; the user pairs later.
        let flag = InMemoryLaunchFlag(hasLaunchedBefore: false)
        var available = false
        let model = AppModel(
            store: store,
            authenticator: FakeAuthenticator(),
            launchFlag: flag,
            isProtectedDataAvailable: { available }
        )
        model.start()
        await model.didBecomeActive()
        let connection = try connection()
        try store.save(connection, token: "device-token")
        model.didPair(connection)
        available = true
        model.didEnterBackground()

        await model.didBecomeActive()

        #expect(try store.load()?.connection == connection)
    }

    @Test func aFreshInstallThatCannotClearTheStoreDoesNotMarkTheLaunch() async {
        let flag = InMemoryLaunchFlag(hasLaunchedBefore: false)
        let model = makeModel(store: ConnectionStore(secrets: UndeletableStore()), launchFlag: flag)
        model.start()

        await model.didBecomeActive()

        #expect(!flag.hasLaunchedBefore)
    }
}
