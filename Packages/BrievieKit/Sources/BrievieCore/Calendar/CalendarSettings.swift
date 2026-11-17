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
    /// The account the workspace's calendar is in: the only one it may be made again in. `nil` for a setting
    /// stored before the account was.
    func sourceID(for workspace: UUID) -> String?
    func enable(workspace: UUID, calendarID: String, sourceID: String?)
    /// Turns the switch off (calendar and account); the description choice stays.
    func disable(workspace: UUID)
    /// Forgets every switch and every description choice.
    func removeAll()
    /// Changes every time `removeAll()` runs (in this process): read it before a calendar is chosen.
    func clearGeneration() -> Int
    /// Stores the calendar only when `removeAll()` did not run since `generation` was read (an unpair while the
    /// switch was being turned on); `false` and nothing stored otherwise.
    func enable(workspace: UUID, calendarID: String, sourceID: String?, ifGeneration generation: Int) -> Bool
    /// "Toon de omschrijving in de agenda": events carry the task's description and sender. Off by default.
    func showsDetails(for workspace: UUID) -> Bool
    func setShowsDetails(_ shows: Bool, for workspace: UUID)
    /// Calendars still to remove after a revocation (calendar identifier to its workspace). Kept apart from the
    /// switches: `removeAll()` leaves them, so a removal that could not run (no access, the app ended) is tried
    /// again.
    func pendingRemovals() -> [String: UUID]
    func markForRemoval(_ calendars: [String: UUID])
    func removalDone(calendarID: String)
}

extension CalendarSettings {
    /// A setting without its account, as stored before the account was.
    public func enable(workspace: UUID, calendarID: String) {
        enable(workspace: workspace, calendarID: calendarID, sourceID: nil)
    }

    public func enable(workspace: UUID, calendarID: String, ifGeneration generation: Int) -> Bool {
        enable(workspace: workspace, calendarID: calendarID, sourceID: nil, ifGeneration: generation)
    }
}

/// `CalendarSettings` over `UserDefaults`: `calendar.<workspace-uuid>` (the calendar) and
/// `calendarSource.<workspace-uuid>` (its account) per workspace that is on, `calendarDetails.<workspace-uuid>`
/// per workspace whose events show the description.
public struct UserDefaultsCalendarSettings: CalendarSettings {
    private static let prefix = "calendar."
    private static let sourcePrefix = "calendarSource."
    private static let detailsPrefix = "calendarDetails."
    private static let pendingRemovalPrefix = "calendarPendingRemoval."
    /// The clears in this process per defaults suite (`""` is the standard defaults); also the lock that makes
    /// "check the generation, then store" one step. Per suite, so separate suites (tests) never disturb each other.
    private static let generations = Mutex<[String: Int]>([:])
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

    public func sourceID(for workspace: UUID) -> String? {
        defaults.string(forKey: Self.sourcePrefix + workspace.uuidString)
    }

    public func enable(workspace: UUID, calendarID: String, sourceID: String?) {
        Self.store(calendarID, sourceID: sourceID, for: workspace, in: defaults)
    }

    public func disable(workspace: UUID) {
        defaults.removeObject(forKey: Self.key(workspace))
        defaults.removeObject(forKey: Self.sourcePrefix + workspace.uuidString)
    }

    public func removeAll() {
        let defaults = defaults
        Self.generations.withLock { generations in
            generations[suiteKey, default: 0] += 1
            let prefixes = [Self.prefix, Self.sourcePrefix, Self.detailsPrefix]
            for key in defaults.dictionaryRepresentation().keys where prefixes.contains(where: key.hasPrefix) {
                defaults.removeObject(forKey: key)
            }
        }
    }

    public func showsDetails(for workspace: UUID) -> Bool {
        defaults.bool(forKey: Self.detailsPrefix + workspace.uuidString)
    }

    public func setShowsDetails(_ shows: Bool, for workspace: UUID) {
        if shows {
            defaults.set(true, forKey: Self.detailsPrefix + workspace.uuidString)
        } else {
            defaults.removeObject(forKey: Self.detailsPrefix + workspace.uuidString)
        }
    }

    public func pendingRemovals() -> [String: UUID] {
        var result: [String: UUID] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(Self.pendingRemovalPrefix) {
            if let text = value as? String, let workspace = UUID(uuidString: text) {
                result[String(key.dropFirst(Self.pendingRemovalPrefix.count))] = workspace
            }
        }
        return result
    }

    public func markForRemoval(_ calendars: [String: UUID]) {
        let defaults = defaults
        for (calendarID, workspace) in calendars {
            defaults.set(workspace.uuidString, forKey: Self.pendingRemovalPrefix + calendarID)
        }
    }

    public func removalDone(calendarID: String) {
        defaults.removeObject(forKey: Self.pendingRemovalPrefix + calendarID)
    }

    public func clearGeneration() -> Int {
        Self.generations.withLock { $0[suiteKey] ?? 0 }
    }

    public func enable(workspace: UUID, calendarID: String, sourceID: String?, ifGeneration generation: Int) -> Bool {
        let defaults = defaults
        return Self.generations.withLock { generations in
            guard generations[suiteKey] ?? 0 == generation else { return false }
            Self.store(calendarID, sourceID: sourceID, for: workspace, in: defaults)
            return true
        }
    }

    private var suiteKey: String { suiteName ?? "" }

    private static func store(_ calendarID: String, sourceID: String?, for workspace: UUID, in defaults: UserDefaults) {
        defaults.set(calendarID, forKey: key(workspace))
        if let sourceID {
            defaults.set(sourceID, forKey: sourcePrefix + workspace.uuidString)
        } else {
            defaults.removeObject(forKey: sourcePrefix + workspace.uuidString)
        }
    }

    private static func key(_ workspace: UUID) -> String {
        prefix + workspace.uuidString
    }
}

/// `CalendarSettings` in memory, for tests and previews.
public final class InMemoryCalendarSettings: CalendarSettings {
    private struct State {
        var ids: [UUID: String] = [:]
        var sources: [UUID: String] = [:]
        var details: Set<UUID> = []
        var pendingRemovals: [String: UUID] = [:]
        var generation = 0
    }

    private let calendars = Mutex(State())

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

    public func sourceID(for workspace: UUID) -> String? {
        calendars.withLock { $0.sources[workspace] }
    }

    public func enable(workspace: UUID, calendarID: String, sourceID: String?) {
        calendars.withLock { state in
            state.ids[workspace] = calendarID
            state.sources[workspace] = sourceID
        }
    }

    public func disable(workspace: UUID) {
        calendars.withLock { state in
            state.ids[workspace] = nil
            state.sources[workspace] = nil
        }
    }

    public func removeAll() {
        calendars.withLock { state in
            state.ids.removeAll()
            state.sources.removeAll()
            state.details.removeAll()
            state.generation += 1
        }
    }

    public func showsDetails(for workspace: UUID) -> Bool {
        calendars.withLock { $0.details.contains(workspace) }
    }

    public func setShowsDetails(_ shows: Bool, for workspace: UUID) {
        calendars.withLock { state in
            if shows { state.details.insert(workspace) } else { state.details.remove(workspace) }
        }
    }

    public func pendingRemovals() -> [String: UUID] {
        calendars.withLock { $0.pendingRemovals }
    }

    public func markForRemoval(_ calendars: [String: UUID]) {
        self.calendars.withLock { $0.pendingRemovals.merge(calendars) { _, new in new } }
    }

    public func removalDone(calendarID: String) {
        calendars.withLock { $0.pendingRemovals[calendarID] = nil }
    }

    public func clearGeneration() -> Int {
        calendars.withLock { $0.generation }
    }

    public func enable(workspace: UUID, calendarID: String, sourceID: String?, ifGeneration generation: Int) -> Bool {
        calendars.withLock { state in
            guard state.generation == generation else { return false }
            state.ids[workspace] = calendarID
            state.sources[workspace] = sourceID
            return true
        }
    }
}
