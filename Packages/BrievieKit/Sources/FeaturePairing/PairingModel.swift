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

    public private(set) var phase: Phase = .scanning

    private let service: PairingService
    private let deviceName: @MainActor () -> String
    private let onPaired: @MainActor (ServerConnection) -> Void
    /// The last valid payload, kept for `retry()`.
    private var lastPayload: PairingPayload?

    /// - Parameters:
    ///   - deviceName: the name the server shows for this device (the app passes the device's name).
    ///   - onPaired: called with the stored connection, also when the task was cancelled after the server
    ///     accepted the code: the pairing then exists and must not be dropped.
    public init(
        service: PairingService,
        deviceName: @escaping @MainActor () -> String,
        onPaired: @escaping @MainActor (ServerConnection) -> Void
    ) {
        self.service = service
        self.deviceName = deviceName
        self.onPaired = onPaired
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
