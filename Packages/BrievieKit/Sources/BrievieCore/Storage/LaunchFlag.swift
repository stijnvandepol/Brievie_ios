import Foundation
import Synchronization

/// Remembers that the app has started at least once since it was installed.
///
/// Keychain items survive uninstalling the app, `UserDefaults` does not: a missing flag therefore means
/// "fresh install", and the app clears whatever pairing the previous install left behind. The flag is the one
/// sanctioned use of `UserDefaults`; it holds a boolean, never a secret (see `docs/DECISIONS.md`).
public protocol LaunchFlag: Sendable {
    var hasLaunchedBefore: Bool { get }
    func markLaunched()
}

/// `LaunchFlag` over `UserDefaults`.
public struct UserDefaultsLaunchFlag: LaunchFlag {
    private let suiteName: String?
    private let key: String

    /// - Parameter suiteName: `nil` for the app's standard defaults; tests pass their own suite.
    public init(suiteName: String? = nil, key: String = "hasLaunchedBefore") {
        self.suiteName = suiteName
        self.key = key
    }

    // `UserDefaults` is not `Sendable`, so the struct keeps the suite name and opens the defaults per call.
    private var defaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public var hasLaunchedBefore: Bool { defaults.bool(forKey: key) }

    public func markLaunched() {
        defaults.set(true, forKey: key)
    }
}

/// `LaunchFlag` for tests.
public final class InMemoryLaunchFlag: LaunchFlag {
    private let value: Mutex<Bool>

    public init(hasLaunchedBefore: Bool) {
        value = Mutex(hasLaunchedBefore)
    }

    public var hasLaunchedBefore: Bool { value.withLock { $0 } }

    public func markLaunched() {
        value.withLock { $0 = true }
    }
}
