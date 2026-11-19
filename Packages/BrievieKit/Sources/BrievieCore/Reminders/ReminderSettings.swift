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
    /// The catch-ups planned so far (a first notice made late), so each is made once.
    func catchUps() -> [ReminderIdentity: CatchUp]
    func setCatchUps(_ catchUps: [ReminderIdentity: CatchUp])
    /// Back to the defaults: off, three days, no sender, no catch-ups.
    func removeAll()
}

extension ReminderSettings {
    /// A stored lead time the settings no longer offer reads as the default.
    static func validLead(_ days: Int?) -> Int {
        guard let days, ReminderPlanner.leadOptions.contains(days) else { return ReminderPlanner.defaultLeadDays }
        return days
    }

    /// `<workspace>|<task>` = `<day>|<deadline>`, all ids and ISO days: plain strings for `UserDefaults`.
    static func encode(_ catchUps: [ReminderIdentity: CatchUp]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: catchUps.map { identity, catchUp in
            (
                "\(identity.workspaceID.uuidString)|\(identity.taskID.uuidString)",
                "\(catchUp.day.iso)|\(catchUp.deadline.iso)"
            )
        })
    }

    static func decode(_ stored: [String: String]) -> [ReminderIdentity: CatchUp] {
        var result: [ReminderIdentity: CatchUp] = [:]
        for (key, value) in stored {
            let ids = key.split(separator: "|").compactMap { UUID(uuidString: String($0)) }
            let days = value.split(separator: "|").compactMap { CalendarDate(iso: String($0)) }
            guard ids.count == 2, days.count == 2 else { continue }
            result[ReminderIdentity(workspaceID: ids[0], taskID: ids[1])] = CatchUp(day: days[0], deadline: days[1])
        }
        return result
    }
}

/// `ReminderSettings` over `UserDefaults`: `reminders.enabled`, `reminders.leadDays`, `reminders.showsSender`.
public struct UserDefaultsReminderSettings: ReminderSettings {
    private static let enabledKey = "reminders.enabled"
    private static let leadKey = "reminders.leadDays"
    private static let senderKey = "reminders.showsSender"
    private static let catchUpsKey = "reminders.catchUps"
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

    public func catchUps() -> [ReminderIdentity: CatchUp] {
        Self.decode(defaults.dictionary(forKey: Self.catchUpsKey) as? [String: String] ?? [:])
    }

    public func setCatchUps(_ catchUps: [ReminderIdentity: CatchUp]) {
        if catchUps.isEmpty {
            defaults.removeObject(forKey: Self.catchUpsKey)
        } else {
            defaults.set(Self.encode(catchUps), forKey: Self.catchUpsKey)
        }
    }

    public func removeAll() {
        let defaults = defaults
        for key in [Self.enabledKey, Self.leadKey, Self.senderKey, Self.catchUpsKey] {
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
        var catchUps: [ReminderIdentity: CatchUp] = [:]
    }

    private let state = Mutex(State())

    public init() {}

    public func isEnabled() -> Bool { state.withLock { $0.enabled } }
    public func setEnabled(_ enabled: Bool) { state.withLock { $0.enabled = enabled } }
    public func leadDays() -> Int { Self.validLead(state.withLock { $0.lead }) }
    public func setLeadDays(_ days: Int) { state.withLock { $0.lead = Self.validLead(days) } }
    public func showsSender() -> Bool { state.withLock { $0.sender } }
    public func setShowsSender(_ shows: Bool) { state.withLock { $0.sender = shows } }
    public func catchUps() -> [ReminderIdentity: CatchUp] { state.withLock { $0.catchUps } }
    public func setCatchUps(_ catchUps: [ReminderIdentity: CatchUp]) { state.withLock { $0.catchUps = catchUps } }
    public func removeAll() { state.withLock { $0 = State() } }
}
