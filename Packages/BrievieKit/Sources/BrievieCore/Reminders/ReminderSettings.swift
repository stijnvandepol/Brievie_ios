import Foundation
import Synchronization

/// "Herinneringen voor termijnen" on this phone: on or off (off by default), how many days before, and whether
/// the sender is shown (off by default).
///
/// Not a secret: the fourth sanctioned use of `UserDefaults` (see `docs/DECISIONS.md`). Forgetting the pairing
/// (unpairing, or the server revoking the device) clears it, like the calendar switches.
public protocol ReminderSettings: Sendable {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool)
    /// Days before the deadline for the first reminder, one of `ReminderPlanner.leadOptions`; 0 is the day only.
    func leadDays() -> Int
    func setLeadDays(_ days: Int)
    /// "Toon de afzender in herinneringen".
    func showsSender() -> Bool
    func setShowsSender(_ shows: Bool)
    /// Back to the defaults: off, three days, no sender.
    func removeAll()
}

extension ReminderSettings {
    /// A stored lead time the settings no longer offer reads as the default.
    static func validLead(_ days: Int?) -> Int {
        guard let days, ReminderPlanner.leadOptions.contains(days) else { return ReminderPlanner.defaultLeadDays }
        return days
    }
}

/// `ReminderSettings` over `UserDefaults`: `reminders.enabled`, `reminders.leadDays`, `reminders.showsSender`.
public struct UserDefaultsReminderSettings: ReminderSettings {
    private static let enabledKey = "reminders.enabled"
    private static let leadKey = "reminders.leadDays"
    private static let senderKey = "reminders.showsSender"
    private let suiteName: String?

    /// - Parameter suiteName: `nil` for the app's standard defaults; tests pass their own suite.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    // `UserDefaults` is not `Sendable`, so the struct keeps the suite name and opens the defaults per call.
    private var defaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public func isEnabled() -> Bool {
        defaults.bool(forKey: Self.enabledKey)
    }

    public func setEnabled(_ enabled: Bool) {
        set(enabled, Self.enabledKey)
    }

    public func leadDays() -> Int {
        Self.validLead(defaults.object(forKey: Self.leadKey) as? Int)
    }

    public func setLeadDays(_ days: Int) {
        defaults.set(Self.validLead(days), forKey: Self.leadKey)
    }

    public func showsSender() -> Bool {
        defaults.bool(forKey: Self.senderKey)
    }

    public func setShowsSender(_ shows: Bool) {
        set(shows, Self.senderKey)
    }

    public func removeAll() {
        let defaults = defaults
        for key in [Self.enabledKey, Self.leadKey, Self.senderKey] {
            defaults.removeObject(forKey: key)
        }
    }

    /// `false` is stored as no key, so the defaults hold only what was turned on.
    private func set(_ value: Bool, _ key: String) {
        if value { defaults.set(true, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

/// `ReminderSettings` in memory, for tests and previews.
public final class InMemoryReminderSettings: ReminderSettings {
    private struct State {
        var enabled = false
        var lead: Int?
        var sender = false
    }

    private let state = Mutex(State())

    public init() {}

    public func isEnabled() -> Bool { state.withLock { $0.enabled } }
    public func setEnabled(_ enabled: Bool) { state.withLock { $0.enabled = enabled } }
    public func leadDays() -> Int { Self.validLead(state.withLock { $0.lead }) }
    public func setLeadDays(_ days: Int) { state.withLock { $0.lead = Self.validLead(days) } }
    public func showsSender() -> Bool { state.withLock { $0.sender } }
    public func setShowsSender(_ shows: Bool) { state.withLock { $0.sender = shows } }
    public func removeAll() { state.withLock { $0 = State() } }
}
