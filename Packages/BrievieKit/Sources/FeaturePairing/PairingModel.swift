import BrievieCore
import Foundation
import Observation

/// Drives the pairing screen: turns scanned or pasted text into a paired connection, or a Dutch explanation.
@MainActor
@Observable
public final class PairingModel {
    public enum Phase: Equatable {
        case scanning
        case pairing
        /// `canRetry`: the scanned code is still worth trying again (the server was not reachable).
        case failed(message: String, canRetry: Bool)
    }

    /// What the screen does with the camera.
    public enum Camera: Equatable {
        /// Permission and support are being looked at.
        case checking
        case scanning
        /// Access was refused: the screen explains, offers Settings and the paste route.
        case denied
        /// No scanner on this device, or it failed to start: the paste route only.
        case unavailable
    }

    public private(set) var phase: Phase = .scanning
    public private(set) var camera: Camera = .checking

    private let service: PairingService
    private let access: any CameraAccess
    private let deviceName: @MainActor () -> String
    private let settingsOpener: @MainActor () -> Void
    private let onPaired: @MainActor (ServerConnection) -> Void
    /// A pairing started for a view. The model owns it and nothing cancels it when the screen goes away:
    /// once the server has accepted the code the pairing must be stored and reported, whatever the view does.
    @ObservationIgnored private(set) var pairingTask: Task<Void, Never>?
    private var isPreparingCamera = false
    /// The last valid payload, kept for `retry()`.
    private var lastPayload: PairingPayload?

    /// - Parameters:
    ///   - camera: the camera permission and scanner support.
    ///   - deviceName: the name the server shows for this device (the app passes the device's name).
    ///   - openSettings: opens the app's page in the Settings app (for a refused camera permission).
    ///   - onPaired: called with the stored connection, also when the task was cancelled after the server
    ///     accepted the code: the pairing then exists and must not be dropped.
    public init(
        service: PairingService,
        camera: any CameraAccess,
        deviceName: @escaping @MainActor () -> String,
        openSettings: @escaping @MainActor () -> Void,
        onPaired: @escaping @MainActor (ServerConnection) -> Void
    ) {
        self.service = service
        self.access = camera
        self.deviceName = deviceName
        self.settingsOpener = openSettings
        self.onPaired = onPaired
    }

    /// Looks at the camera permission and, the first time, asks for it. Called when the screen appears and
    /// when the app becomes active again (the user may have changed the permission in Settings).
    public func prepareCamera() async {
        guard !isPreparingCamera else { return }
        isPreparingCamera = true
        defer { isPreparingCamera = false }
        if access.status() == .notDetermined {
            _ = await access.requestAccess()
        }
        switch access.status() {
        case .authorized: camera = .scanning
        // Still undetermined after asking: treat it as a refusal rather than waiting for ever.
        case .denied, .notDetermined: camera = .denied
        case .unsupported: camera = .unavailable
        }
    }

    /// The scanner could not start: pasting is the way forward.
    public func scannerFailed() {
        camera = .unavailable
        phase = .failed(message: PairingStrings.generic, canRetry: false)
    }

    public func openSettings() {
        settingsOpener()
    }

    // MARK: - Entry points for views

    /// Pairs with scanned text. Not cancelled when the view goes away (see `pairingTask`).
    public func startPairing(scanned text: String) {
        pairingTask = Task { await scanned(text) }
    }

    /// Pairs with pasted text. Not cancelled when the view goes away (see `pairingTask`).
    public func startPairing(pasted text: String) {
        pairingTask = Task { await submitManual(text) }
    }

    /// Retries the last payload. Not cancelled when the view goes away (see `pairingTask`).
    public func startRetry() {
        pairingTask = Task { await retry() }
    }

    /// Text from the camera or the paste field. Anything that is not a Brievie code is explained and the
    /// scanner keeps running; the camera reports the same code many times, so a pairing in progress ignores it.
    public func scanned(_ text: String) async {
        guard phase != .pairing else { return }
        let payload: PairingPayload
        do {
            payload = try PairingPayload.parse(text)
        } catch {
            phase = .failed(message: Self.message(for: error), canRetry: false)
            return
        }
        lastPayload = payload
        await pair(payload)
    }

    /// Runs the last valid payload again after a failure that allows it.
    public func retry() async {
        guard case .failed(_, canRetry: true) = phase, let lastPayload else { return }
        await pair(lastPayload)
    }

    public func submitManual(_ text: String) async {
        await scanned(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func pair(_ payload: PairingPayload) async {
        phase = .pairing
        let name = deviceName().trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let connection = try await service.pair(payload, deviceName: name.isEmpty ? "iPhone" : name)
            lastPayload = nil
            phase = .scanning
            onPaired(connection)
        } catch .cancelled {
            phase = .scanning
        } catch {
            phase = Self.phase(for: error)
        }
    }

    private static func phase(for error: PairingError) -> Phase {
        switch error {
        case .noServerReachable: .failed(message: PairingStrings.unreachable, canRetry: true)
        case .serverNotVerified: .failed(message: PairingStrings.notVerified, canRetry: false)
        case .invalidCode: .failed(message: PairingStrings.invalidCode, canRetry: false)
        case .connectionLostWhilePairing: .failed(message: PairingStrings.connectionLost, canRetry: false)
        case .tooManyAttempts: .failed(message: PairingStrings.tooManyAttempts, canRetry: true)
        case .incompatibleServer: .failed(message: PairingStrings.incompatible, canRetry: false)
        case .cancelled: .scanning
        case .failed: .failed(message: PairingStrings.generic, canRetry: false)
        }
    }

    private static func message(for error: PairingPayloadError) -> String {
        switch error {
        case .notBrievie: PairingStrings.notBrievie
        case .unsupportedVersion: PairingStrings.unsupportedVersion
        case .invalid: PairingStrings.invalid
        }
    }
}
