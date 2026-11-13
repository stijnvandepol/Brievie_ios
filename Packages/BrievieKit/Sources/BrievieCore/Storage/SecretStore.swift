import Foundation

public enum SecretKey: String, Sendable {
    case deviceToken
    case serverConnection
}

/// Storage for secrets. In the app this is the Keychain (`KeychainSecretStore`); tests use `InMemorySecretStore`.
public protocol SecretStore: Sendable {
    /// The stored data, or `nil` when nothing is stored for `key`.
    func read(_ key: SecretKey) throws -> Data?
    /// Stores `data`, replacing what was stored for `key`.
    func write(_ data: Data, for key: SecretKey) throws
    /// Removes what was stored for `key`; removing a missing item is not an error.
    func delete(_ key: SecretKey) throws
}
