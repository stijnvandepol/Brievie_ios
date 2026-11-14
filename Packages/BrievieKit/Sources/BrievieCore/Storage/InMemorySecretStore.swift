import Foundation
import Synchronization

/// A `SecretStore` that keeps everything in memory, for tests and previews.
public final class InMemorySecretStore: SecretStore {
    private let items = Mutex<[SecretKey: Data]>([:])

    public init() {}

    public func read(_ key: SecretKey) -> Data? {
        items.withLock { $0[key] }
    }

    public func write(_ data: Data, for key: SecretKey) {
        items.withLock { $0[key] = data }
    }

    public func delete(_ key: SecretKey) {
        items.withLock { $0[key] = nil }
    }
}
