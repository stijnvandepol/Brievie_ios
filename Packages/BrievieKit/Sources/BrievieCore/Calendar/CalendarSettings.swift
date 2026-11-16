import Foundation
import Synchronization

/// The calendar switch per workspace: on means "this calendar identifier is Brievie's for that workspace".
///
/// The identifier is not a secret; next to `hasLaunchedBefore` this is the second sanctioned use of
/// `UserDefaults` (see `docs/DECISIONS.md`). Unpairing clears it; the calendars themselves stay.
public protocol CalendarSettings: Sendable {
    func calendarID(for workspace: UUID) -> String?
    /// The calendar of every workspace that is on.
    func calendarIDs() -> [UUID: String]
    func isEnabled(for workspace: UUID) -> Bool
    func enable(workspace: UUID, calendarID: String)
    func disable(workspace: UUID)
    func removeAll()
}

/// `CalendarSettings` over `UserDefaults`: one key `calendar.<workspace-uuid>` per workspace that is on.
public struct UserDefaultsCalendarSettings: CalendarSettings {
    private static let prefix = "calendar."
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
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private static func key(_ workspace: UUID) -> String {
        prefix + workspace.uuidString
    }
}

/// `CalendarSettings` in memory, for tests and previews.
public final class InMemoryCalendarSettings: CalendarSettings {
    private let calendars = Mutex<[UUID: String]>([:])

    public init() {}

    public func calendarID(for workspace: UUID) -> String? {
        calendars.withLock { $0[workspace] }
    }

    public func calendarIDs() -> [UUID: String] {
        calendars.withLock { $0 }
    }

    public func isEnabled(for workspace: UUID) -> Bool {
        calendarID(for: workspace) != nil
    }

    public func enable(workspace: UUID, calendarID: String) {
        calendars.withLock { $0[workspace] = calendarID }
    }

    public func disable(workspace: UUID) {
        calendars.withLock { $0[workspace] = nil }
    }

    public func removeAll() {
        calendars.withLock { $0.removeAll() }
    }
}
