import BrievieCore
import Foundation
import Synchronization

/// An authenticator whose answers are set per test. `onAuthenticate` runs while the prompt is "on screen".
final class FakeAuthenticator: DeviceAuthenticator {
    private struct State {
        var availability = AuthenticationAvailability.available
        var succeeds = true
        var prompts = 0
        var reasons: [String] = []
    }

    private let state = Mutex(State())
    private let onAuthenticate: @Sendable () async -> Void

    init(onAuthenticate: @escaping @Sendable () async -> Void = {}) {
        self.onAuthenticate = onAuthenticate
    }

    var availabilityValue: AuthenticationAvailability {
        get { state.withLock { $0.availability } }
        set { state.withLock { $0.availability = newValue } }
    }

    var succeeds: Bool {
        get { state.withLock { $0.succeeds } }
        set { state.withLock { $0.succeeds = newValue } }
    }

    var prompts: Int { state.withLock { $0.prompts } }
    var reasons: [String] { state.withLock { $0.reasons } }

    func availability() -> AuthenticationAvailability {
        state.withLock { $0.availability }
    }

    func authenticate(reason: String) async -> Bool {
        state.withLock {
            $0.prompts += 1
            $0.reasons.append(reason)
        }
        await onAuthenticate()
        return state.withLock { $0.succeeds }
    }
}

@MainActor
final class ModelBox {
    var model: AppModel?
}

struct UnreadableStore: SecretStore {
    struct Unreadable: Error {}

    func read(_ key: SecretKey) throws -> Data? { throw Unreadable() }
    func write(_ data: Data, for key: SecretKey) throws {}
    func delete(_ key: SecretKey) throws {}
}

struct UndeletableStore: SecretStore {
    struct Undeletable: Error {}

    func read(_ key: SecretKey) throws -> Data? { nil }
    func write(_ data: Data, for key: SecretKey) throws {}
    func delete(_ key: SecretKey) throws { throw Undeletable() }
}
