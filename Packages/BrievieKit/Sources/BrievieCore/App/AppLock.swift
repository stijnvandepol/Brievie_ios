import Foundation
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Asks the device owner to prove who they are. The app lock is built on this seam; the live
/// implementation uses Face ID with the device passcode as fallback.
public protocol DeviceAuthenticator: Sendable {
    /// `false` when the device cannot authenticate its owner at all (no passcode set).
    func canAuthenticate() -> Bool
    /// Shows the system prompt (`deviceOwnerAuthentication`: biometrics, then the device passcode).
    func authenticate(reason: String) async -> Bool
}

#if canImport(LocalAuthentication)
/// `DeviceAuthenticator` over LocalAuthentication.
public struct LocalAuthenticator: DeviceAuthenticator {
    public init() {}

    public func canAuthenticate() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
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
