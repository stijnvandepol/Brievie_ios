import BrievieCore
@testable import FeaturePairing
import Foundation
import Synchronization
import Testing

/// A `BrievieServer` for pairing tests: every URL answers as a public-certificate server unless set otherwise.
final class StubServer: BrievieServer {
    private struct State {
        var healthCalls = 0
        var pairCalls = 0
        var deviceNames: [String] = []
        var health: @Sendable () throws -> String = { "1.0.0" }
        var pair: @Sendable () throws -> PairedDevice = { StubServer.device }
    }

    static let device = PairedDevice(deviceID: UUID(), token: "device-token", userName: "Beheerder")

    private let state = Mutex(State())

    var healthCalls: Int { state.withLock { $0.healthCalls } }
    var pairCalls: Int { state.withLock { $0.pairCalls } }
    var deviceNames: [String] { state.withLock { $0.deviceNames } }

    var health: @Sendable () throws -> String {
        get { state.withLock { $0.health } }
        set { state.withLock { $0.health = newValue } }
    }

    var pair: @Sendable () throws -> PairedDevice {
        get { state.withLock { $0.pair } }
        set { state.withLock { $0.pair = newValue } }
    }

    func health(at url: URL, trust: ServerTrust) async throws -> String {
        let answer = state.withLock {
            $0.healthCalls += 1
            return $0.health
        }
        return try answer()
    }

    func caCertificatePEM(at url: URL) async throws -> String {
        throw ServerError.other("not expected: the payload has no CA")
    }

    func pair(at url: URL, trust: ServerTrust, code: String, deviceName: String) async throws -> PairedDevice {
        let answer = state.withLock {
            $0.pairCalls += 1
            $0.deviceNames.append(deviceName)
            return $0.pair
        }
        return try answer()
    }

    func workspaces(at url: URL, trust: ServerTrust, token: String) async throws -> [WorkspaceSummary] {
        []
    }
}

@MainActor
@Suite struct PairingModelTests {
    static let validPayload = #"{"v":1,"urls":["https://brievie.local"],"code":"ABCD-EFGH","ca_sha256":null}"#

    private let server = StubServer()
    private let secrets = InMemorySecretStore()
    private let paired = Paired()
    private let camera = FakeCamera(.authorized)

    @MainActor
    final class Paired {
        var connections: [ServerConnection] = []
    }

    private func makeModel(deviceName: String = "Stijns iPhone") -> PairingModel {
        let paired = paired
        return PairingModel(
            service: PairingService(server: server, store: ConnectionStore(secrets: secrets)),
            camera: camera,
            deviceName: { deviceName },
            openSettings: {},
            onPaired: { paired.connections.append($0) }
        )
    }

    // MARK: - Review Focus 1: not a Brievie code

    @Test(arguments: ["https://example.com", "WIFI:S:home;T:WPA;P:secret;;", "", "{\"hello\":1}"])
    func aCodeThatIsNotBrievieIsRefusedAndTheScannerKeepsRunning(text: String) async {
        let model = makeModel()

        await model.scanned(text)

        #expect(model.phase == .failed(
            message: "Dit is geen Brievie-code. Open in de webinterface 'App koppelen' en scan de code daar.",
            canRetry: false
        ))
        #expect(server.healthCalls == 0)
        #expect(secrets.read(.deviceToken) == nil)
        #expect(paired.connections.isEmpty)
    }

    @Test func aValidScanStillWorksAfterANonBrievieCode() async {
        let model = makeModel()
        await model.scanned("https://example.com")

        await model.scanned(Self.validPayload)

        #expect(paired.connections.count == 1)
        #expect(secrets.read(.deviceToken) != nil)
    }

    // MARK: - pairing

    @Test func aValidScanPairsAndReportsTheConnection() async {
        let model = makeModel(deviceName: "Stijns iPhone")

        await model.scanned(Self.validPayload)

        #expect(paired.connections.map(\.userName) == ["Beheerder"])
        #expect(server.deviceNames == ["Stijns iPhone"])
    }

    @Test func anEmptyDeviceNameFallsBackToTheModelName() async {
        let model = makeModel(deviceName: "  ")

        await model.scanned(Self.validPayload)

        #expect(server.deviceNames == ["iPhone"])
    }

    @Test func pastedTextIsTrimmed() async {
        let model = makeModel()

        await model.submitManual("  \n\(Self.validPayload)\n ")

        #expect(paired.connections.count == 1)
    }

    @Test func theSameCodeScannedTwiceInARowPairsOnce() async {
        // The camera reports the same code many times a second.
        let model = makeModel()

        async let first: Void = model.scanned(Self.validPayload)
        async let second: Void = model.scanned(Self.validPayload)
        _ = await (first, second)

        #expect(server.pairCalls == 1)
        #expect(paired.connections.count == 1)
    }

    // MARK: - Review Focus 4: nothing reachable

    @Test func unreachableOffersARetryThatKeepsThePayload() async {
        server.health = { throw ServerError.unreachable }
        let model = makeModel()

        await model.scanned(Self.validPayload)

        #expect(model.phase == .failed(
            message: "We kunnen je Brievie-server niet bereiken. Zit je op hetzelfde netwerk?",
            canRetry: true
        ))
        #expect(server.healthCalls == 1)

        server.health = { "1.0.0" }
        await model.retry()

        #expect(server.healthCalls == 2)
        #expect(paired.connections.count == 1)
    }

    @Test func retryDoesNothingWithoutAPayload() async {
        let model = makeModel()

        await model.retry()

        #expect(model.phase == .scanning)
        #expect(server.healthCalls == 0)
    }

    @Test func retryDoesNothingWhenTheFailureHasNoRetry() async {
        server.pair = { throw ServerError.invalidCode }
        let model = makeModel()
        await model.scanned(Self.validPayload)

        await model.retry()

        #expect(server.pairCalls == 1)
    }

    // MARK: - messages

    @Test func aServerThatCannotBeVerifiedIsReportedWithoutRetry() async {
        server.health = { throw ServerError.untrusted }
        let model = makeModel()

        await model.scanned(Self.validPayload)

        #expect(model.phase == .failed(
            message: "We konden niet controleren of dit jouw Brievie-server is. "
                + "Maak een nieuwe code en probeer het opnieuw.",
            canRetry: false
        ))
    }

    @Test func aRejectedCodeAsksForANewOne() async {
        server.pair = { throw ServerError.invalidCode }
        let model = makeModel()

        await model.scanned(Self.validPayload)

        #expect(model.phase == .failed(
            message: "Deze code is verlopen of al gebruikt. Maak een nieuwe code.",
            canRetry: false
        ))
    }

    @Test(arguments: [ServerError.unreachable, .untrusted])
    func aConnectionThatDropsWhileSendingTheCodeAsksForANewCode(error: ServerError) async {
        server.pair = { throw error }
        let model = makeModel()

        await model.scanned(Self.validPayload)

        #expect(model.phase == .failed(
            message: "De verbinding viel weg tijdens het koppelen. Maak een nieuwe code en probeer het opnieuw.",
            canRetry: false
        ))
    }

    @Test func diagnosticTextNeverReachesTheUser() async {
        server.pair = { throw ServerError.other("http_503_secret_detail") }
        let model = makeModel()

        await model.scanned(Self.validPayload)

        #expect(model.phase == .failed(message: "Er ging iets mis. Probeer het opnieuw.", canRetry: false))
    }

    @Test func tooManyAttemptsAndIncompatibleServersHaveTheirOwnMessage() async {
        server.pair = { throw ServerError.tooManyAttempts }
        let throttled = makeModel()
        await throttled.scanned(Self.validPayload)
        #expect(throttled.phase == .failed(
            message: "Er zijn te veel pogingen gedaan. Wacht even en probeer het opnieuw.", canRetry: true
        ))

        server.health = { "2.0.0" }
        let incompatible = makeModel()
        await incompatible.scanned(Self.validPayload)
        #expect(incompatible.phase == .failed(
            message: "Deze server en de app passen niet bij elkaar. Werk de app of de server bij.", canRetry: false
        ))
    }

    // MARK: - cancellation

    @Test func aCancelledPairingGoesBackToScanning() async {
        server.health = { throw CancellationError() }
        let model = makeModel()

        await model.scanned(Self.validPayload)

        #expect(model.phase == .scanning)
        #expect(paired.connections.isEmpty)
    }

    @Test func aPairingThatSucceededDespiteCancellationIsStillUsed() async {
        // The server accepted the code and the service stored the pairing before the cancel was noticed:
        // dropping the result would leave a paired device the app does not know about.
        server.pair = {
            withUnsafeCurrentTask { $0?.cancel() }
            return StubServer.device
        }
        let model = makeModel()

        await Task { await model.scanned(Self.validPayload) }.value

        #expect(paired.connections.count == 1)
        #expect(secrets.read(.deviceToken) != nil)
    }

    // MARK: - copy

    @Test func viewTextsInTheCatalogUseTheNewWording() throws {
        let expected = [
            "pairing.title": "Koppelen met je server",
            "pairing.instructions": "Open in de webinterface Apparaten en maak een koppelcode.",
            "pairing.scan": "Scan QR-code",
            "pairing.manual.field": "Plak de koppelgegevens",
            "pairing.paste.show": "Plak koppelgegevens",
            "pairing.camera.denied":
                "Brievie mag de camera niet gebruiken. Zet dit aan in Instellingen, of plak de koppelgegevens.",
            "pairing.camera.openSettings": "Open Instellingen",
            "pairing.camera.restricted": "De camera is op dit toestel uitgeschakeld. Plak de koppelgegevens."
        ]
        for (key, value) in expected {
            #expect(try CatalogParity.dutchValue(forKey: key, target: "FeaturePairing") == value, "\(key)")
        }
    }

    @Test func catalogAndCodeAgree() throws {
        for (key, resolved) in PairingStrings.all {
            #expect(try CatalogParity.dutchValue(forKey: key, target: "FeaturePairing") == resolved, "\(key)")
        }
    }
}
