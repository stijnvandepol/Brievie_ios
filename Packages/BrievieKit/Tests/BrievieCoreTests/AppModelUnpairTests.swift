@testable import BrievieCore
import BrievieScan
import Foundation
import Testing

/// "Ontkoppelen": tell the server (best effort), empty the upload queue, forget the pairing.
@MainActor
@Suite struct AppModelUnpairTests {
    private let secrets = FlakyDeleteStore()
    private var store: ConnectionStore { ConnectionStore(secrets: secrets) }
    private let server: FakeBrievieServer
    private let transport = FakeUploadTransport()
    private let directory = FileManager.default.temporaryDirectory.appending(path: "unpair-\(UUID().uuidString)")
    private let uploads: UploadCoordinator
    private let home: URL
    private let away: URL
    private let connection: ServerConnection

    init() throws {
        server = try FakeBrievieServer()
        home = try #require(URL(string: "https://brievie.local"))
        away = try #require(URL(string: "https://brievie.example.nl"))
        connection = ServerConnection(urls: [home, away], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn")
        let store = ConnectionStore(secrets: secrets)
        try store.save(connection, token: "device-token")
        uploads = UploadCoordinator(
            store: UploadQueueStore(directory: directory),
            transport: transport,
            connection: { try store.load().map { ($0.connection, $0.token) } },
            onRevoked: { _ in }
        )
    }

    private func unpairing(timeout: Duration = .seconds(5)) -> Unpairing {
        Unpairing(server: server, uploads: uploads, timeout: timeout)
    }

    /// Paired and unlocked: the only state in which the settings (and their button) are usable.
    private func readyModel(_ authenticator: FakeAuthenticator = FakeAuthenticator()) async -> AppModel {
        let model = AppModel(
            store: store,
            authenticator: authenticator,
            launchFlag: InMemoryLaunchFlag(hasLaunchedBefore: true),
            isProtectedDataAvailable: { true }
        )
        model.start()
        await model.unlock()
        return model
    }

    private func queueTwoScans() async throws {
        let page = [ScannedPage(jpeg: Data([0xFF, 0xD8, 0xFF, 1]), text: "tekst")]
        _ = try await uploads.enqueue(pages: page, workspaceID: UUID())
        _ = try await uploads.enqueue(pages: page, workspaceID: UUID())
    }

    private func queueEntries() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
    }

    private func expectNothingStored(sourceLocation: SourceLocation = #_sourceLocation) throws {
        #expect(try store.load() == nil, sourceLocation: sourceLocation)
        #expect(try secrets.read(.deviceToken) == nil, sourceLocation: sourceLocation)
        #expect(try secrets.read(.serverConnection) == nil, sourceLocation: sourceLocation)
    }

    // MARK: - The server is told

    @Test func aReachableServerRevokesTheDeviceAndNothingIsLeft() async throws {
        try await queueTwoScans()
        let model = await readyModel()
        #expect(await unpairing().queuedScanCount() == 2)

        let unpaired = await model.unpair(unpairing())

        #expect(unpaired)
        #expect(server.revokeCalls == [.revoke(home, deviceID: connection.deviceID, token: "device-token")])
        #expect(transport.cancelled.count == 2)
        #expect(await uploads.items().isEmpty)
        #expect(queueEntries().isEmpty)
        try expectNothingStored()
        #expect(model.state == .unpaired(notice: nil))
        #expect(!model.isUnpairing)
    }

    @Test func theNextAddressIsTriedWhenTheFirstIsUnreachable() async throws {
        let home = home
        server.revoke = { url in if url == home { throw ServerError.unreachable } }
        let model = await readyModel()

        await model.unpair(unpairing())

        #expect(server.revokeCalls.count == 2)
        #expect(model.state == .unpaired(notice: nil))
    }

    @Test(arguments: [ServerError.unauthorized, .other("device_not_found")])
    func aServerThatNoLongerKnowsTheDeviceCountsAsTold(answer: ServerError) async throws {
        server.revoke = { _ in throw answer }
        let model = await readyModel()

        await model.unpair(unpairing())

        #expect(server.revokeCalls.count == 1)
        try expectNothingStored()
        #expect(model.state == .unpaired(notice: nil))
    }

    // MARK: - The server is not told

    @Test func offlineStillUnpairsAndSaysTheServerStillKnowsThePhone() async throws {
        try await queueTwoScans()
        server.revoke = { _ in throw ServerError.unreachable }
        let model = await readyModel()

        let unpaired = await model.unpair(unpairing())

        #expect(unpaired)
        #expect(server.revokeCalls.count == 2)
        #expect(await uploads.items().isEmpty)
        #expect(queueEntries().isEmpty)
        try expectNothingStored()
        #expect(model.state == .unpaired(notice: AppStrings.serverStillKnowsDevice))
        #expect(AppStrings.serverStillKnowsDevice == """
            Deze telefoon staat nog als apparaat op de server. Trek hem daar in onder Apparaten.
            """)
    }

    @Test(arguments: [ServerError.untrusted, .other("http_403"), .other("http_404"), .other("http_500")])
    func anyOtherRefusalStillUnpairsWithTheNotice(answer: ServerError) async throws {
        server.revoke = { _ in throw answer }
        let model = await readyModel()

        await model.unpair(unpairing())

        try expectNothingStored()
        #expect(model.state == .unpaired(notice: AppStrings.serverStillKnowsDevice))
    }

    @Test func aServerThatDoesNotAnswerIsGivenUpOnAfterTheTimeout() async throws {
        server.revoke = { _ in try await Task.sleep(for: .seconds(60)) }
        let model = await readyModel()
        let clock = ContinuousClock()
        let start = clock.now

        await model.unpair(unpairing(timeout: .milliseconds(100)))

        #expect(clock.now - start < .seconds(10))
        try expectNothingStored()
        #expect(model.state == .unpaired(notice: AppStrings.serverStillKnowsDevice))
    }

    // MARK: - Failures: never half paired

    @Test func aQueueThatCannotBeEmptiedKeepsTheAppLockedUntilARetrySucceeds() async throws {
        try await queueTwoScans()
        let model = await readyModel()
        let path = directory.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path) }

        let unpaired = await model.unpair(unpairing())

        #expect(!unpaired)
        #expect(model.state == .locked)
        // The pairing is not forgotten before its scans are: no pairing screen with scans left behind.
        #expect(try store.load() != nil)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        model.didEnterBackground()
        await model.didBecomeActive()

        #expect(queueEntries().isEmpty)
        try expectNothingStored()
        #expect(model.state == .unpaired(notice: nil))
    }

    @Test func aStoreThatCannotBeClearedKeepsTheAppLockedUntilARetrySucceeds() async throws {
        let authenticator = FakeAuthenticator()
        let model = await readyModel(authenticator)
        secrets.deleteFails = true

        let unpaired = await model.unpair(unpairing())

        #expect(!unpaired)
        #expect(model.state == .locked)
        #expect(try secrets.read(.deviceToken) != nil)

        // Still failing: the unlock button retries instead of opening the app.
        await model.unlock()
        #expect(model.state == .locked)

        secrets.deleteFails = false
        await model.unlock()

        try expectNothingStored()
        #expect(model.state == .unpaired(notice: nil))
        // Only the unlock at the start asked for Face ID; the retries never open the app.
        #expect(authenticator.prompts == 1)
    }

    @Test func aRetryKeepsTheNoticeOfTheServerThatWasNotTold() async throws {
        server.revoke = { _ in throw ServerError.unreachable }
        let model = await readyModel()
        secrets.deleteFails = true

        await model.unpair(unpairing())
        secrets.deleteFails = false
        await model.unlock()

        #expect(model.state == .unpaired(notice: AppStrings.serverStillKnowsDevice))
    }

    // MARK: - Only once, only when open

    @Test func aDoubleTapUnpairsOnce() async throws {
        let model = await readyModel()

        async let first = model.unpair(unpairing())
        async let second = model.unpair(unpairing())
        let results = await [first, second]

        #expect(results.sorted { !$0 && $1 } == [false, true])
        #expect(server.revokeCalls.count == 1)
    }

    @Test func requestUnpairTwiceRunsOnce() async throws {
        let model = await readyModel()

        model.requestUnpair(unpairing())
        model.requestUnpair(unpairing())
        await model.unpairTask?.value

        #expect(server.revokeCalls.count == 1)
        #expect(model.state == .unpaired(notice: nil))
    }

    @Test func aLockedAppDoesNotUnpair() async throws {
        let model = await readyModel()
        model.didEnterBackground()

        let unpaired = await model.unpair(unpairing())

        #expect(!unpaired)
        #expect(server.revokeCalls.isEmpty)
        #expect(try store.load() != nil)
        #expect(model.state == .locked)
    }

    @Test func aRevocationReportedWhileUnpairingDoesNotOvertakeIt() async throws {
        let box = ModelBox()
        let deviceID = connection.deviceID
        server.revoke = { _ in await MainActor.run { box.model?.sessionRevoked(deviceID: deviceID) } }
        let model = await readyModel()
        box.model = model

        await model.unpair(unpairing())

        #expect(model.state == .unpaired(notice: nil))
    }

    // MARK: - The revoked path shares the clear-or-stay-locked rule

    @Test func aRevocationWhoseClearFailsStaysLockedAndRetries() async throws {
        let model = await readyModel()
        secrets.deleteFails = true

        model.sessionRevoked(deviceID: connection.deviceID)

        #expect(model.state == .locked)
        #expect(try secrets.read(.deviceToken) != nil)

        secrets.deleteFails = false
        model.didEnterBackground()
        await model.didBecomeActive()

        try expectNothingStored()
        #expect(model.state == .unpaired(notice: AppStrings.sessionRevoked))
    }
}
