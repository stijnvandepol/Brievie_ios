@testable import BrievieCore
import Foundation
import Synchronization
import Testing

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

    private func makeModel(
        _ authenticator: FakeAuthenticator = FakeAuthenticator(),
        store: ConnectionStore? = nil,
        launchFlag: InMemoryLaunchFlag = InMemoryLaunchFlag(hasLaunchedBefore: true),
        protectedDataAvailable: Bool = true
    ) -> AppModel {
        AppModel(
            store: store ?? self.store,
            authenticator: authenticator,
            launchFlag: launchFlag,
            isProtectedDataAvailable: { protectedDataAvailable }
        )
    }

    // MARK: - start

    @Test func startIsUnpairedWithAnEmptyStore() {
        let model = makeModel()

        model.start()

        #expect(model.state == .unpaired(notice: nil))
    }

    @Test func startIsLockedWithAStoredConnection() throws {
        _ = try pairedStore()
        let model = makeModel()

        model.start()

        #expect(model.state == .locked)
    }

    // MARK: - unlock

    @Test func unlockSuccessOpensTheApp() async throws {
        let connection = try pairedStore()
        let authenticator = FakeAuthenticator()
        let model = makeModel(authenticator)
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
        let model = makeModel(authenticator)
        model.start()

        await model.unlock()

        #expect(model.state == .locked)
    }

    // MARK: - Review Focus 5: no passcode

    @Test func withoutAPasscodeTheAppOpensWithAWarning() async throws {
        let connection = try pairedStore()
        let authenticator = FakeAuthenticator()
        authenticator.availabilityValue = .noPasscode
        let model = makeModel(authenticator)
        model.start()

        await model.unlock()

        #expect(model.state == .ready(connection))
        #expect(model.showsNoPasscodeWarning)
        #expect(authenticator.prompts == 0)
    }

    @Test func theWarningGoesAwayOnceTheDeviceHasAPasscode() async throws {
        _ = try pairedStore()
        let authenticator = FakeAuthenticator()
        authenticator.availabilityValue = .noPasscode
        let model = makeModel(authenticator)
        model.start()
        await model.unlock()
        model.didEnterBackground()
        authenticator.availabilityValue = .available

        await model.unlock()

        #expect(!model.showsNoPasscodeWarning)
    }

    @Test func pairingOnADeviceWithoutPasscodeShowsTheWarning() throws {
        let authenticator = FakeAuthenticator()
        authenticator.availabilityValue = .noPasscode
        let model = makeModel(authenticator)
        model.start()

        model.didPair(try connection())

        #expect(model.showsNoPasscodeWarning)
    }

    // MARK: - locking

    @Test func pairingOpensTheAppWithoutAPrompt() throws {
        let authenticator = FakeAuthenticator()
        let model = makeModel(authenticator)
        model.start()
        let connection = try connection()

        model.didPair(connection)

        #expect(model.state == .ready(connection))
        #expect(authenticator.prompts == 0)
    }

    @Test func goingToTheBackgroundLocksTheApp() async throws {
        _ = try pairedStore()
        let model = makeModel()
        model.start()
        await model.unlock()

        model.didEnterBackground()

        #expect(model.state == .locked)
    }

    @Test func backgroundDoesNotLockAnUnpairedApp() {
        let model = makeModel()
        model.start()

        model.didEnterBackground()

        #expect(model.state == .unpaired(notice: nil))
    }

    @Test func unlockingDoesNotLockTheAppAgain() async throws {
        // Face ID's own sheet makes the scene inactive but never backgrounds it: nothing but the
        // background callback may lock, so a finished unlock stays unlocked.
        let connection = try pairedStore()
        let model = makeModel()
        model.start()

        await model.didBecomeActive()
        await model.didBecomeActive()

        #expect(model.state == .ready(connection))
    }

    @Test func backgroundDuringThePromptDiscardsTheResult() async throws {
        _ = try pairedStore()
        let box = ModelBox()
        let authenticator = FakeAuthenticator { await box.model?.didEnterBackground() }
        let model = makeModel(authenticator)
        box.model = model
        model.start()

        await model.unlock()

        #expect(model.state == .locked)
    }

    @Test func activationPromptsOncePerLaunchOrBackground() async throws {
        _ = try pairedStore()
        let authenticator = FakeAuthenticator()
        authenticator.succeeds = false
        let model = makeModel(authenticator)
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
        let model = makeModel(authenticator)
        model.start()

        async let first: Void = model.unlock()
        async let second: Void = model.unlock()
        _ = await (first, second)

        #expect(authenticator.prompts == 1)
    }

    // MARK: - Review Focus 6: revoked

    @Test func sessionRevokedClearsTheStoreAndExplains() async throws {
        let connection = try pairedStore()
        let model = makeModel()
        model.start()
        await model.unlock()

        model.sessionRevoked(deviceID: connection.deviceID)

        #expect(model.state == .unpaired(
            notice: "Deze koppeling werkt niet meer: ze is ingetrokken of je hebt Brievie lang niet gebruikt. "
                + "Koppel dit toestel opnieuw om verder te gaan."
        ))
        #expect(try store.load() == nil)
        #expect(secrets.read(.deviceToken) == nil)
        #expect(secrets.read(.serverConnection) == nil)
    }

    @Test func pairingAfterARevocationLeavesTheNoticeBehind() throws {
        let old = try pairedStore()
        let model = makeModel()
        model.start()
        model.sessionRevoked(deviceID: old.deviceID)
        let connection = try connection()

        model.didPair(connection)

        #expect(model.state == .ready(connection))
    }

    @Test func aStoreThatCannotBeReadKeepsTheAppLockedInsteadOfUnpairing() {
        let model = makeModel(store: ConnectionStore(secrets: UnreadableStore()))

        model.start()

        #expect(model.state == .locked)
    }
}
