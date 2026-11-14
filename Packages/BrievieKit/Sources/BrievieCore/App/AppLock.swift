import Foundation
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Whether `DeviceAuthenticator` can ask the device owner to prove who they are.
public enum AuthenticationAvailability: Sendable, Equatable {
    case available
    /// The device has no passcode at all: nothing to ask, and nothing that could lock the app.
    case noPasscode
    /// Authentication failed for any other reason (for example a transient system error): do not open the app.
    case unavailable
}

/// Asks the device owner to prove who they are. The app lock is built on this seam; the live
/// implementation uses Face ID with the device passcode as fallback.
public protocol DeviceAuthenticator: Sendable {
    /// Whether the device can authenticate its owner right now. Only `.noPasscode` may open the app without
    /// a prompt; any other reason the check fails is `.unavailable` and keeps the app locked.
    func availability() -> AuthenticationAvailability
    /// Shows the system prompt (`deviceOwnerAuthentication`: biometrics, then the device passcode).
    func authenticate(reason: String) async -> Bool
}

#if canImport(LocalAuthentication)
/// `DeviceAuthenticator` over LocalAuthentication.
public struct LocalAuthenticator: DeviceAuthenticator {
    public init() {}

    public func availability() -> AuthenticationAvailability {
        var error: NSError?
        if LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            return .available
        }
        return Self.availability(for: error)
    }

    /// `LAError.passcodeNotSet` is the only error that means "no passcode".
    static func availability(for error: NSError?) -> AuthenticationAvailability {
        guard let error, error.domain == LAError.errorDomain, error.code == LAError.passcodeNotSet.rawValue else {
            return .unavailable
        }
        return .noPasscode
    }

    public func authenticate(reason: String) async -> Bool {
        do {
            return try await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
#endif
