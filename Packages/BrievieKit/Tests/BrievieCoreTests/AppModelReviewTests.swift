@testable import BrievieCore
import Foundation
import Testing

/// Behaviour added by the final review: background pairing, authenticator availability, unlock failures,
/// stale revocations, first launch and the tasks the model owns for views.
@MainActor
@Suite struct AppModelReviewTests {
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
        launchFlag: InMemoryLaunchFlag = InMemoryLaunchFlag(hasLaunchedBefore: true)
    ) -> AppModel {
        AppModel(store: store ?? self.store, authenticator: authenticator, launchFlag: launchFlag)
    }

    // MARK: - Final review: pairing in the background

    @Test func pairingWhileInTheBackgroundLocksTheApp() async throws {
        let authenticator = FakeAuthenticator()
        let model = makeModel(authenticator)
        model.start()
        await model.didBecomeActive()
        model.didEnterBackground()
        let connection = try connection()
        try store.save(connection, token: "device-token")

        model.didPair(connection)

        #expect(model.state == .locked)

        await model.didBecomeActive()

        #expect(authenticator.prompts == 1)
        #expect(model.state == .ready(connection))
    }

    @Test func pairingInTheForegroundOpensTheAppAfterAReturnFromTheBackground() async throws {
        let authenticator = FakeAuthenticator()
        let model = makeModel(authenticator)
        model.start()
        model.didEnterBackground()
        await model.didBecomeActive()
        let connection = try connection()

        model.didPair(connection)

        #expect(model.state == .ready(connection))
        #expect(authenticator.prompts == 0)
    }

    // MARK: - Final review: only noPasscode means "no passcode"

    @Test func anUnavailableAuthenticatorKeepsTheAppLocked() async throws {
        _ = try pairedStore()
        let authenticator = FakeAuthenticator()
        authenticator.availabilityValue = .unavailable
        let model = makeModel(authenticator)
        model.start()

        await model.unlock()

        #expect(model.state == .locked)
        #expect(!model.showsNoPasscodeWarning)
        #expect(authenticator.prompts == 0)
    }

    @Test func anUnavailableAuthenticatorCanBeRetriedLater() async throws {
        let connection = try pairedStore()
        let authenticator = FakeAuthenticator()
        authenticator.availabilityValue = .unavailable
        let model = makeModel(authenticator)
        model.start()
        await model.unlock()
        authenticator.availabilityValue = .available

        await model.unlock()

        #expect(model.state == .ready(connection))
    }

    // MARK: - Final review: finishUnlock

    @Test func aStoreThatCannotBeReadAfterUnlockingStaysLocked() async {
        let authenticator = FakeAuthenticator()
        let model = makeModel(authenticator, store: ConnectionStore(secrets: UnreadableStore()))
        model.start()

        await model.unlock()

        #expect(authenticator.prompts == 1)
        #expect(model.state == .locked)
    }

    @Test func aMissingPairingAfterUnlockingUsesTheGenericMessage() async throws {
        _ = try pairedStore()
        let model = makeModel()
        model.start()
        try store.clear()

        await model.unlock()

        #expect(model.state == .unpaired(notice: "Er ging iets mis. Probeer het opnieuw."))
    }

    @Test func aMissingPairingIsNotReportedAsRevoked() throws {
        let model = makeModel()
        model.start()

        model.connectionMissing()

        #expect(model.state == .unpaired(notice: "Er ging iets mis. Probeer het opnieuw."))
    }

    // MARK: - Final review: stale revocation

    @Test func aRevocationOfTheCurrentDeviceUnpairs() throws {
        let connection = try pairedStore()
        let model = makeModel()
        model.start()

        model.sessionRevoked(deviceID: connection.deviceID)

        #expect(model.state == .unpaired(
            notice: "Dit apparaat is ontkoppeld. Koppel het opnieuw om verder te gaan."
        ))
        #expect(try store.load() == nil)
    }

    @Test func aRevocationOfAnOlderDeviceLeavesTheNewPairingAlone() throws {
        let old = try connection()
        let fresh = try connection()
        try store.save(fresh, token: "fresh-token")
        let model = makeModel()
        model.start()
        model.didPair(fresh)

        model.sessionRevoked(deviceID: old.deviceID)

        #expect(model.state == .ready(fresh))
        #expect(secrets.read(.deviceToken) == Data("fresh-token".utf8))
    }

    @Test func aRevocationWhenTheStoreCannotBeReadChangesNothing() throws {
        let connection = try connection()
        let model = makeModel(store: ConnectionStore(secrets: UnreadableStore()))
        model.didPair(connection)

        model.sessionRevoked(deviceID: connection.deviceID)

        #expect(model.state == .ready(connection))
    }

    // MARK: - Final review: first launch after an install

    @Test func aFreshInstallStartsUnpairedAndClearsLeftoverKeychainItems() throws {
        _ = try pairedStore()
        let flag = InMemoryLaunchFlag(hasLaunchedBefore: false)
        let model = makeModel(launchFlag: flag)

        model.start()

        #expect(model.state == .unpaired(notice: nil))
        #expect(secrets.read(.deviceToken) == nil)
        #expect(secrets.read(.serverConnection) == nil)
        #expect(flag.hasLaunchedBefore)
    }

    @Test func aNormalRelaunchKeepsThePairing() throws {
        _ = try pairedStore()
        let flag = InMemoryLaunchFlag(hasLaunchedBefore: false)
        makeModel(launchFlag: flag).start()
        let connection = try connection()
        try store.save(connection, token: "device-token")

        let relaunched = makeModel(launchFlag: flag)
        relaunched.start()

        #expect(relaunched.state == .locked)
        #expect(try store.load()?.connection == connection)
    }

    @Test func aFreshInstallThatCannotClearTheStoreDoesNotMarkTheLaunch() {
        let flag = InMemoryLaunchFlag(hasLaunchedBefore: false)
        let model = makeModel(store: ConnectionStore(secrets: UndeletableStore()), launchFlag: flag)

        model.start()

        #expect(!flag.hasLaunchedBefore)
    }

    // MARK: - Final review: tasks owned by the model

    @Test func requestUnlockRunsTheUnlock() async throws {
        let connection = try pairedStore()
        let model = makeModel()
        model.start()

        model.requestUnlock()
        await model.pendingTask?.value

        #expect(model.state == .ready(connection))
    }

    @Test func sceneActivationPromptsAtLaunch() async throws {
        let connection = try pairedStore()
        let model = makeModel()
        model.start()

        model.sceneActivated()
        await model.pendingTask?.value

        #expect(model.state == .ready(connection))
    }
}
