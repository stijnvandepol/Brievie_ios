import Foundation

/// Whether Brievie may read and write the user's calendars. Write-only access counts as `.denied`: the sync
/// must read the events it made.
public enum CalendarAccess: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
}

/// An account on the phone that can hold a new calendar.
public struct CalendarSource: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The user's own iCloud account.
        case iCloud
        /// "Op mijn iPhone": stays on this phone.
        case local
        /// Exchange, Google or any other CalDAV account: someone else runs its server, perhaps an employer.
        case other
    }

    public let id: String
    /// As the phone names it ("iCloud", "Gmail", "Werk").
    public let title: String
    public let kind: Kind

    public init(id: String, title: String, kind: Kind) {
        self.id = id
        self.title = title
        self.kind = kind
    }
}

/// The accounts that can hold a new calendar, and the account of the phone's default calendar.
public struct CalendarSourceList: Equatable, Sendable {
    public let sources: [CalendarSource]
    public let defaultSourceID: String?

    public init(sources: [CalendarSource], defaultSourceID: String?) {
        self.sources = sources
        self.defaultSourceID = defaultSourceID
    }

    public func source(id: String) -> CalendarSource? {
        sources.first { $0.id == id }
    }
}

/// Where a new Brievie calendar may go. iCloud and the phone itself are the user's own: chosen without asking
/// (the default calendar's account when it is one of them, else iCloud, else the phone). Any other account is
/// run by someone else, who can read what is in it: only after the user said yes to that account by name.
public enum CalendarSourceChoice: Equatable, Sendable {
    case silent(CalendarSource)
    /// The default calendar's account, or else the first other account.
    case needsConsent(CalendarSource)
    /// The phone has no account that takes a new calendar.
    case none

    public init(sources: [CalendarSource], defaultSourceID: String?) {
        let fallback = sources.first { $0.id == defaultSourceID }
        if let fallback, fallback.kind != .other {
            self = .silent(fallback)
        } else if let own = sources.first(where: { $0.kind == .iCloud })
            ?? sources.first(where: { $0.kind == .local }) {
            self = .silent(own)
        } else if let other = fallback ?? sources.first {
            self = .needsConsent(other)
        } else {
            self = .none
        }
    }

    public init(_ list: CalendarSourceList) {
        self.init(sources: list.sources, defaultSourceID: list.defaultSourceID)
    }
}

/// A calendar and the account it is in.
public struct CalendarRef: Equatable, Sendable {
    public let id: String
    public let sourceID: String

    public init(id: String, sourceID: String) {
        self.id = id
        self.sourceID = sourceID
    }
}

/// The phone's calendars, as far as the sync uses them. `EventKitCalendarStore` is the live one.
public protocol CalendarStore: Sendable {
    func access() async -> CalendarAccess
    /// Asks the user (once; afterwards the system answers with the earlier choice).
    func requestAccess() async -> CalendarAccess
    /// The accounts that can hold a new calendar (never a subscribed or birthday calendar's).
    func sources() async -> CalendarSourceList
    /// The calendar `existingID` when it still exists, is writable and is not in `excluding` (retitled `named`
    /// when the workspace was renamed), in whatever account it is. Else a calendar titled `named` is adopted, but
    /// only when it is in the account `sourceID`, is not in `excluding` (the calendars of other workspaces) and
    /// has no event without a task link in `window` (it is empty, or only Brievie's). Else a new calendar with
    /// that title is made in the account `sourceID`, and nowhere else.
    /// - Throws: `CalendarStoreError(.sourceGone)` when `sourceID` is `nil` or that account is not on the phone.
    func ensureCalendar(
        named: String, existingID: String?, excluding: Set<String>, window: ClosedRange<CalendarDate>,
        sourceID: String?
    ) async throws -> CalendarRef
    /// The events of the calendar `calendarID` on the days of `window`.
    func events(calendarID: String, window: ClosedRange<CalendarDate>) async throws -> [CalendarEventSnapshot]
    /// Writes `changes` into the calendar `calendarID`, all or nothing as far as the store allows.
    func apply(_ changes: [CalendarChange], calendarID: String) async throws
    /// Removes the calendar `id`, but only when it holds no event without a task link on any day of
    /// `CalendarRemoval.checkedDays` (an adopted calendar the user made can hold their own events far outside the
    /// sync window). When it does, only the events with a task link go and the calendar stays.
    func removeCalendar(id: String) async throws -> CalendarRemoval
}

/// What "Verwijderen" did with a workspace's calendar.
public enum CalendarRemoval: Equatable, Sendable {
    /// The calendar is gone (or was gone already).
    case removed
    /// The calendar also holds events of the user: only Brievie's events went, the calendar stays.
    case keptForUserEvents

    /// The days checked for events of the user before a calendar is removed.
    public static let checkedDays =
        CalendarDate(year: 2000, month: 1, day: 1)...CalendarDate(year: 2100, month: 12, day: 31)

    /// `checkedDays` in slices of three years: EventKit searches at most four years at a time.
    public static let querySlices: [ClosedRange<CalendarDate>] = {
        var slices: [ClosedRange<CalendarDate>] = []
        var start = checkedDays.lowerBound
        while start <= checkedDays.upperBound {
            let end = min(start.adding(years: 3).adding(days: -1), checkedDays.upperBound)
            slices.append(start...end)
            start = end.adding(days: 1)
        }
        return slices
    }()
}

public struct CalendarStoreError: Error, Equatable {
    public enum Reason: Equatable, Sendable {
        case failed
        /// The account the calendar must be made in is not on the phone (any more).
        case sourceGone
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
    /// The account of each calendar.
    private var calendarSources: [String: String] = [:]
    private var sourceList: CalendarSourceList
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

    /// The iCloud account the fake has unless a test gives it others.
    public static let iCloud = CalendarSource(id: "icloud", title: "iCloud", kind: .iCloud)

    public init(
        access: CalendarAccess = .granted, grantsOnRequest: Bool = true,
        sources: [CalendarSource] = [FakeCalendarStore.iCloud], defaultSourceID: String? = FakeCalendarStore.iCloud.id
    ) {
        accessState = access
        self.grantsOnRequest = grantsOnRequest
        sourceList = CalendarSourceList(sources: sources, defaultSourceID: defaultSourceID)
    }

    /// The user added or removed accounts, or chose another default calendar.
    public func setSources(_ sources: [CalendarSource], defaultSourceID: String?) {
        sourceList = CalendarSourceList(sources: sources, defaultSourceID: defaultSourceID)
    }

    /// The user removed an account from the phone: its calendars and their events go with it.
    public func userRemovesSource(id: String) {
        for calendar in calendarSources.filter({ $0.value == id }).keys { userDeletesCalendar(id: calendar) }
        sourceList = CalendarSourceList(
            sources: sourceList.sources.filter { $0.id != id },
            defaultSourceID: sourceList.defaultSourceID == id ? nil : sourceList.defaultSourceID
        )
    }

    public func sourceID(ofCalendar id: String) -> String? {
        calendarSources[id]
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
        calendarSources[id] = nil
        calendarOrder.removeAll { $0 == id }
        stored.removeAll { $0.calendarID == id }
    }

    /// The user made a calendar of their own, in the account `sourceID` (`nil`: the default calendar's).
    public func userAddsCalendar(title: String, sourceID: String? = nil) -> String {
        addCalendar(title: title, sourceID: sourceID ?? sourceList.defaultSourceID ?? "")
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

    public func sources() async -> CalendarSourceList {
        sourceList
    }

    public func ensureCalendar(
        named: String, existingID: String?, excluding: Set<String>, window: ClosedRange<CalendarDate>,
        sourceID: String?
    ) async throws -> CalendarRef {
        try check()
        if let existingID, calendars[existingID] != nil, !excluding.contains(existingID) {
            calendars[existingID] = named
            return CalendarRef(id: existingID, sourceID: calendarSources[existingID] ?? "")
        }
        guard let sourceID, sourceList.source(id: sourceID) != nil else { throw CalendarStoreError(.sourceGone) }
        let adoptable = calendarOrder.first { id in
            calendars[id] == named && !excluding.contains(id) && calendarSources[id] == sourceID
                && !hasEventOfTheUser(calendarID: id, window: window)
        }
        return CalendarRef(id: adoptable ?? addCalendar(title: named, sourceID: sourceID), sourceID: sourceID)
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

    public func removeCalendar(id: String) async throws -> CalendarRemoval {
        try check()
        let usersOwn = stored.contains {
            $0.calendarID == id && $0.snapshot.taskID == nil && CalendarRemoval.checkedDays.contains($0.snapshot.day)
        }
        guard usersOwn else {
            userDeletesCalendar(id: id)
            return .removed
        }
        stored.removeAll { $0.calendarID == id && $0.snapshot.taskID != nil }
        return .keptForUserEvents
    }

    private func snapshot(_ task: CalendarTask, eventID: String) -> CalendarEventSnapshot {
        CalendarEventSnapshot(eventID: eventID, taskID: task.id, title: task.title, notes: task.notes, day: task.day)
    }

    private func hasEventOfTheUser(calendarID: String, window: ClosedRange<CalendarDate>) -> Bool {
        stored.contains {
            $0.calendarID == calendarID && $0.snapshot.taskID == nil && window.contains($0.snapshot.day)
        }
    }

    private func addCalendar(title: String, sourceID: String) -> String {
        let id = makeID("calendar")
        calendars[id] = title
        calendarSources[id] = sourceID
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
