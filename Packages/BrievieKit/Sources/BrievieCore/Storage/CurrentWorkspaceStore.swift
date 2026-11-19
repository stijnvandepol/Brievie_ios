import Foundation
import Synchronization

/// The workspace the inbox showed last, per pairing: the app opens on it again.
///
/// Keyed by the pairing's device id, which the server issues per pairing of this phone with one user on one
/// server, so pairing again (or with another server or user) starts from the server's first workspace. The id
/// is not a secret; this is the third sanctioned use of `UserDefaults` (see `docs/DECISIONS.md`). Forgetting
/// the pairing (unpairing, or the server revoking the device) clears it.
public protocol CurrentWorkspaceStore: Sendable {
    /// The workspace last shown under the pairing `device`; `nil` when there is none.
    func workspace(forDevice device: UUID) -> UUID?
    func remember(_ workspace: UUID, forDevice device: UUID)
    /// Forgets the choice of every pairing.
    func removeAll()
}

/// `CurrentWorkspaceStore` over `UserDefaults`: `currentWorkspace.<device-uuid>` = the workspace's id.
public struct UserDefaultsCurrentWorkspaceStore: CurrentWorkspaceStore {
    private static let prefix = "currentWorkspace."
    private let suiteName: String?

    /// - Parameter suiteName: `nil` for the app's standard defaults; tests pass their own suite.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    // `UserDefaults` is not `Sendable`, so the struct keeps the suite name and opens the defaults per call.
    private var defaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public func workspace(forDevice device: UUID) -> UUID? {
        defaults.string(forKey: Self.prefix + device.uuidString).flatMap(UUID.init(uuidString:))
    }

    public func remember(_ workspace: UUID, forDevice device: UUID) {
        defaults.set(workspace.uuidString, forKey: Self.prefix + device.uuidString)
    }

    public func removeAll() {
        let defaults = defaults
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

/// `CurrentWorkspaceStore` in memory, for tests and previews.
public final class InMemoryCurrentWorkspaceStore: CurrentWorkspaceStore {
    private let choices = Mutex<[UUID: UUID]>([:])

    public init() {}

    public func workspace(forDevice device: UUID) -> UUID? {
        choices.withLock { $0[device] }
    }

    public func remember(_ workspace: UUID, forDevice device: UUID) {
        choices.withLock { $0[device] = workspace }
    }

    public func removeAll() {
        choices.withLock { $0.removeAll() }
    }
}
