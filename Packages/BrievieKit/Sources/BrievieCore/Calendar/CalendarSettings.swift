import Foundation
import Synchronization

/// The calendar switch per workspace: on means "this calendar identifier is Brievie's for that workspace".
///
/// The identifier is not a secret; next to `hasLaunchedBefore` this is the second sanctioned use of
/// `UserDefaults` (see `docs/DECISIONS.md`). Forgetting the pairing (unpairing, or the server revoking the
/// device) clears it; the calendars themselves stay unless the user chose to remove them.
public protocol CalendarSettings: Sendable {
    func calendarID(for workspace: UUID) -> String?
    /// The calendar of every workspace that is on.
    func calendarIDs() -> [UUID: String]
    func isEnabled(for workspace: UUID) -> Bool
    func enable(workspace: UUID, calendarID: String)
    func disable(workspace: UUID)
    func removeAll()
    /// Changes every time `removeAll()` runs (in this process): read it before a calendar is chosen.
    func clearGeneration() -> Int
    /// Stores the calendar only when `removeAll()` did not run since `generation` was read (an unpair while the
    /// switch was being turned on); `false` and nothing stored otherwise.
    func enable(workspace: UUID, calendarID: String, ifGeneration generation: Int) -> Bool
}

/// `CalendarSettings` over `UserDefaults`: one key `calendar.<workspace-uuid>` per workspace that is on.
public struct UserDefaultsCalendarSettings: CalendarSettings {
    private static let prefix = "calendar."
    /// The clears in this process; also the lock that makes "check the generation, then store" one step.
    private static let generation = Mutex(0)
    private let suiteName: String?

    /// - Parameter suiteName: `nil` for the app's standard defaults; tests pass their own suite.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    // `UserDefaults` is not `Sendable`, so the struct keeps the suite name and opens the defaults per call.
    private var defaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public func calendarID(for workspace: UUID) -> String? {
        defaults.string(forKey: Self.key(workspace))
    }

    public func calendarIDs() -> [UUID: String] {
        var result: [UUID: String] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(Self.prefix) {
            if let workspace = UUID(uuidString: String(key.dropFirst(Self.prefix.count))), let id = value as? String {
                result[workspace] = id
            }
        }
        return result
    }

    public func isEnabled(for workspace: UUID) -> Bool {
        calendarID(for: workspace) != nil
    }

    public func enable(workspace: UUID, calendarID: String) {
        defaults.set(calendarID, forKey: Self.key(workspace))
    }

    public func disable(workspace: UUID) {
        defaults.removeObject(forKey: Self.key(workspace))
    }

    public func removeAll() {
        let defaults = defaults
        Self.generation.withLock { generation in
            generation += 1
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.prefix) {
                defaults.removeObject(forKey: key)
            }
        }
    }

    public func clearGeneration() -> Int {
        Self.generation.withLock { $0 }
    }

    public func enable(workspace: UUID, calendarID: String, ifGeneration generation: Int) -> Bool {
        let defaults = defaults
        return Self.generation.withLock { current in
            guard current == generation else { return false }
            defaults.set(calendarID, forKey: Self.key(workspace))
            return true
        }
    }

    private static func key(_ workspace: UUID) -> String {
        prefix + workspace.uuidString
    }
}

/// `CalendarSettings` in memory, for tests and previews.
public final class InMemoryCalendarSettings: CalendarSettings {
    private let calendars = Mutex<(ids: [UUID: String], generation: Int)>(([:], 0))

    public init() {}

    public func calendarID(for workspace: UUID) -> String? {
        calendars.withLock { $0.ids[workspace] }
    }

    public func calendarIDs() -> [UUID: String] {
        calendars.withLock { $0.ids }
    }

    public func isEnabled(for workspace: UUID) -> Bool {
        calendarID(for: workspace) != nil
    }

    public func enable(workspace: UUID, calendarID: String) {
        calendars.withLock { $0.ids[workspace] = calendarID }
    }

    public func disable(workspace: UUID) {
        calendars.withLock { $0.ids[workspace] = nil }
    }

    public func removeAll() {
        calendars.withLock { state in
            state.ids.removeAll()
            state.generation += 1
        }
    }

    public func clearGeneration() -> Int {
        calendars.withLock { $0.generation }
    }

    public func enable(workspace: UUID, calendarID: String, ifGeneration generation: Int) -> Bool {
        calendars.withLock { state in
            guard state.generation == generation else { return false }
            state.ids[workspace] = calendarID
            return true
        }
    }
}
