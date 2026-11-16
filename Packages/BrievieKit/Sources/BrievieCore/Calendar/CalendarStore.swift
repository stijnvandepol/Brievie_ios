import Foundation

/// Whether Brievie may read and write the user's calendars. Write-only access counts as `.denied`: the sync
/// must read the events it made.
public enum CalendarAccess: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
}

/// The phone's calendars, as far as the sync uses them. `EventKitCalendarStore` is the live one.
public protocol CalendarStore: Sendable {
    func access() async -> CalendarAccess
    /// Asks the user (once; afterwards the system answers with the earlier choice).
    func requestAccess() async -> CalendarAccess
    /// The calendar `existingID` when it still exists, is writable and is not in `excluding` (retitled `named`
    /// when the workspace was renamed). Else a calendar titled `named` is adopted, but only when it is in the
    /// default calendar source, is not in `excluding` (the calendars of other workspaces) and has no event without
    /// a task link in `window` (it is empty, or only Brievie's). Else a new calendar with that title is made in
    /// the default source. Returns its identifier.
    func ensureCalendar(
        named: String, existingID: String?, excluding: Set<String>, window: ClosedRange<CalendarDate>
    ) async throws -> String
    /// The events of the calendar `calendarID` on the days of `window`.
    func events(calendarID: String, window: ClosedRange<CalendarDate>) async throws -> [CalendarEventSnapshot]
    /// Writes `changes` into the calendar `calendarID`, all or nothing as far as the store allows.
    func apply(_ changes: [CalendarChange], calendarID: String) async throws
    func removeCalendar(id: String) async throws
}

public struct CalendarStoreError: Error, Equatable {
    public enum Reason: Equatable, Sendable {
        case failed
        /// The phone has no calendar source that takes a new calendar (no default calendar, no local or CalDAV
        /// source).
        case noSourceForNewCalendar
    }

    public let reason: Reason

    public init(_ reason: Reason = .failed) {
        self.reason = reason
    }
}

/// `CalendarStore` in memory, for tests and previews. It can refuse access and fail every call.
public actor FakeCalendarStore: CalendarStore {
    private struct StoredEvent {
        var snapshot: CalendarEventSnapshot
        let calendarID: String
    }

    public private(set) var calendars: [String: String] = [:]
    /// Calendar ids in the order they were made: the adoption by title picks the oldest.
    private var calendarOrder: [String] = []
    /// Calendars outside the default calendar source.
    private var otherSource: Set<String> = []
    private var stored: [StoredEvent] = []
    private var accessState: CalendarAccess
    private var grantsOnRequest: Bool
    private var isFailing = false
    private var nextID = 0
    private var runningApplies = 0
    public private(set) var accessChecks = 0
    public private(set) var accessRequests = 0
    /// Every change applied, in order.
    public private(set) var appliedChanges: [CalendarChange] = []
    /// The most `apply` calls that ran at the same time.
    public private(set) var maxConcurrentApplies = 0

    public init(access: CalendarAccess = .granted, grantsOnRequest: Bool = true) {
        accessState = access
        self.grantsOnRequest = grantsOnRequest
    }

    public func setAccess(_ access: CalendarAccess, grantsOnRequest: Bool) {
        accessState = access
        self.grantsOnRequest = grantsOnRequest
    }

    /// From now on every call that can throw fails.
    public func setFailing(_ failing: Bool) {
        isFailing = failing
    }

    /// The events of one calendar, in the order they were made.
    public func storedEvents(calendarID: String) -> [CalendarEventSnapshot] {
        stored.filter { $0.calendarID == calendarID }.map(\.snapshot)
    }

    /// The user deleted a calendar in the Calendar app.
    public func userDeletesCalendar(id: String) {
        calendars[id] = nil
        calendarOrder.removeAll { $0 == id }
        stored.removeAll { $0.calendarID == id }
    }

    /// The user made a calendar of their own, in the default calendar source or in another one.
    public func userAddsCalendar(title: String, inDefaultSource: Bool = true) -> String {
        let id = addCalendar(title: title)
        if !inDefaultSource { otherSource.insert(id) }
        return id
    }

    /// The user added an event (without a Brievie link) to a calendar.
    public func userAddsEvent(title: String, day: CalendarDate, calendarID: String) {
        let snapshot = CalendarEventSnapshot(eventID: makeID("event"), taskID: nil, title: title, notes: "", day: day)
        stored.append(StoredEvent(snapshot: snapshot, calendarID: calendarID))
    }

    public func access() async -> CalendarAccess {
        accessChecks += 1
        return accessState
    }

    public func requestAccess() async -> CalendarAccess {
        accessRequests += 1
        if accessState == .notDetermined {
            accessState = grantsOnRequest ? .granted : .denied
        }
        return accessState
    }

    public func ensureCalendar(
        named: String, existingID: String?, excluding: Set<String>, window: ClosedRange<CalendarDate>
    ) async throws -> String {
        try check()
        if let existingID, calendars[existingID] != nil, !excluding.contains(existingID) {
            calendars[existingID] = named
            return existingID
        }
        let adoptable = calendarOrder.first { id in
            calendars[id] == named && !excluding.contains(id) && !otherSource.contains(id)
                && !hasEventOfTheUser(calendarID: id, window: window)
        }
        return adoptable ?? addCalendar(title: named)
    }

    public func events(calendarID: String, window: ClosedRange<CalendarDate>) async throws -> [CalendarEventSnapshot] {
        try check()
        // Lets other callers in between, as a real store does: the sync must not rely on running alone.
        await Task.yield()
        return storedEvents(calendarID: calendarID).filter { window.contains($0.day) }
    }

    public func apply(_ changes: [CalendarChange], calendarID: String) async throws {
        try check()
        guard calendars[calendarID] != nil else { throw CalendarStoreError() }
        runningApplies += 1
        maxConcurrentApplies = max(maxConcurrentApplies, runningApplies)
        defer { runningApplies -= 1 }
        await Task.yield()
        for change in changes {
            appliedChanges.append(change)
            switch change {
            case .create(let task):
                stored.append(StoredEvent(snapshot: snapshot(task, eventID: makeID("event")), calendarID: calendarID))
            case .update(let eventID, let task):
                if let index = stored.firstIndex(where: { $0.snapshot.eventID == eventID }) {
                    stored[index].snapshot = snapshot(task, eventID: eventID)
                }
            case .delete(let eventID):
                stored.removeAll { $0.snapshot.eventID == eventID }
            }
        }
    }

    public func removeCalendar(id: String) async throws {
        try check()
        userDeletesCalendar(id: id)
    }

    private func snapshot(_ task: CalendarTask, eventID: String) -> CalendarEventSnapshot {
        CalendarEventSnapshot(eventID: eventID, taskID: task.id, title: task.title, notes: task.notes, day: task.day)
    }

    private func hasEventOfTheUser(calendarID: String, window: ClosedRange<CalendarDate>) -> Bool {
        stored.contains {
            $0.calendarID == calendarID && $0.snapshot.taskID == nil && window.contains($0.snapshot.day)
        }
    }

    private func addCalendar(title: String) -> String {
        let id = makeID("calendar")
        calendars[id] = title
        calendarOrder.append(id)
        return id
    }

    private func check() throws {
        if isFailing { throw CalendarStoreError() }
    }

    private func makeID(_ prefix: String) -> String {
        nextID += 1
        return "\(prefix)-\(nextID)"
    }
}
