import BrievieCore
@testable import FeaturePairing
import Foundation
import Testing

/// A camera whose permission state is set per test; asking for access answers with `grantsAccess`.
@MainActor
final class FakeCamera: CameraAccess {
    var current: CameraStatus
    var grantsAccess = true
    private(set) var requests = 0

    init(_ status: CameraStatus) {
        current = status
    }

    func status() -> CameraStatus { current }

    func requestAccess() async -> Bool {
        requests += 1
        current = grantsAccess ? .authorized : .denied
        return grantsAccess
    }
}

@MainActor
@Suite struct PairingCameraTests {
    private let server = StubServer()
    private let secrets = InMemorySecretStore()
    private let paired = PairingModelTests.Paired()
    private let camera = FakeCamera(.authorized)
    private let settings = SettingsOpens()

    @MainActor
    final class SettingsOpens {
        var count = 0
    }

    private func makeModel() -> PairingModel {
        let paired = paired
        return PairingModel(
            service: PairingService(server: server, store: ConnectionStore(secrets: secrets)),
            camera: camera,
            deviceName: { "Stijns iPhone" },
            openSettings: { [settings] in settings.count += 1 },
            onPaired: { paired.connections.append($0) }
        )
    }

    // MARK: - camera access

    @Test func theCameraIsBeingCheckedUntilTheModelHasLooked() {
        #expect(makeModel().camera == .checking)
    }

    @Test func anAuthorizedCameraStartsTheScannerWithoutAsking() async {
        let model = makeModel()

        await model.prepareCamera()

        #expect(model.camera == .scanning)
        #expect(camera.requests == 0)
    }

    @Test func aFirstTimeUserIsAskedAndGetsTheScannerWhenTheyAgree() async {
        camera.current = .notDetermined
        let model = makeModel()

        await model.prepareCamera()

        #expect(camera.requests == 1)
        #expect(model.camera == .scanning)
    }

    @Test func aFirstTimeUserWhoRefusesGetsTheDeniedState() async {
        camera.current = .notDetermined
        camera.grantsAccess = false
        let model = makeModel()

        await model.prepareCamera()

        #expect(camera.requests == 1)
        #expect(model.camera == .denied)
    }

    @Test func aDeniedCameraIsNotAskedAgainAndOffersSettings() async {
        camera.current = .denied
        let model = makeModel()

        await model.prepareCamera()
        model.openSettings()

        #expect(model.camera == .denied)
        #expect(camera.requests == 0)
        #expect(settings.count == 1)
    }

    @Test func aDeviceWithoutAScannerFallsBackToPasting() async {
        camera.current = .unsupported
        let model = makeModel()

        await model.prepareCamera()

        #expect(model.camera == .unavailable)
        #expect(camera.requests == 0)
    }

    @Test func allowingTheCameraInSettingsStartsTheScannerOnTheNextCheck() async {
        camera.current = .denied
        let model = makeModel()
        await model.prepareCamera()

        camera.current = .authorized
        await model.prepareCamera()

        #expect(model.camera == .scanning)
    }

    @Test func aScannerThatCannotStartFallsBackToPastingWithTheGenericError() async {
        let model = makeModel()
        await model.prepareCamera()

        model.scannerFailed()

        #expect(model.camera == .unavailable)
        #expect(model.phase == .failed(message: "Er ging iets mis. Probeer het opnieuw.", canRetry: false))
    }

    // MARK: - owned tasks

    @Test func aPairingStartedForAViewIsOwnedByTheModel() async {
        let model = makeModel()

        model.startPairing(scanned: PairingModelTests.validPayload)
        await model.pairingTask?.value

        #expect(paired.connections.count == 1)
    }

    @Test func aPastedPairingStartedForAViewIsTrimmed() async {
        let model = makeModel()

        model.startPairing(pasted: " \(PairingModelTests.validPayload) \n")
        await model.pairingTask?.value

        #expect(paired.connections.count == 1)
    }

    @Test func aRetryStartedForAViewRunsTheLastPayloadAgain() async {
        server.health = { throw ServerError.unreachable }
        let model = makeModel()
        await model.scanned(PairingModelTests.validPayload)
        server.health = { "1.0.0" }

        model.startRetry()
        await model.pairingTask?.value

        #expect(paired.connections.count == 1)
    }
}
