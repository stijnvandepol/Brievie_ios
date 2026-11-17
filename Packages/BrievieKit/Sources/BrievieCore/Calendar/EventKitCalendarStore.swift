import EventKit
import Foundation
import OSLog

/// `CalendarStore` over EventKit. One `EKEventStore`, used only inside this actor.
///
/// Events are all-day, on the deadline, with the task link as their URL and three alarms at 09:00 local time:
/// 7 days before, 2 days before and on the day. Never used by the unit tests (they must not ask for access).
public actor EventKitCalendarStore: CalendarStore {
    /// Seconds from the start of the all-day event (00:00 on the deadline).
    private static let alarmOffsets: [TimeInterval] = [-7 * 86_400 + 9 * 3_600, -2 * 86_400 + 9 * 3_600, 9 * 3_600]

    private static let logger = Logger(subsystem: "nl.stijnvdpol.brievie", category: "calendar")

    private let eventStore = EKEventStore()
    /// The store was reset after access was granted. A store made before the first grant (in the prompt, or in
    /// Settings while the app ran) can keep answering without calendars or a default calendar until then.
    private var isFreshAfterGrant = false

    public init() {}

    public func access() async -> CalendarAccess {
        let access = Self.access(EKEventStore.authorizationStatus(for: .event))
        if access == .granted { resetOnceAfterGrant() }
        return access
    }

    public func requestAccess() async -> CalendarAccess {
        do {
            guard try await eventStore.requestFullAccessToEvents() else { return .denied }
            resetOnceAfterGrant()
            return .granted
        } catch {
            return .denied
        }
    }

    public func ensureCalendar(
        named: String, existingID: String?, excluding: Set<String>, window: ClosedRange<CalendarDate>
    ) async throws -> String {
        if let existingID, !excluding.contains(existingID),
           let calendar = eventStore.calendar(withIdentifier: existingID), calendar.allowsContentModifications {
            if calendar.title != named {
                // The workspace was renamed (or the user retitled the calendar). Best effort: never fails a sync.
                calendar.title = named
                do {
                    try eventStore.saveCalendar(calendar, commit: true)
                } catch {
                    eventStore.reset()
                    Self.logger.error("Could not retitle the calendar: \(String(describing: type(of: error)))")
                }
            }
            return existingID
        }
        if let match = adoptableCalendar(named: named, excluding: excluding, window: window) {
            return match.calendarIdentifier
        }
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = named
        // The default calendar's source, then iCloud, then the local source (see `candidateSources()`).
        var lastError: (any Error)?
        for source in candidateSources() {
            calendar.source = source
            do {
                try eventStore.saveCalendar(calendar, commit: true)
                return calendar.calendarIdentifier
            } catch {
                lastError = error
            }
        }
        throw lastError ?? CalendarStoreError(.noSourceForNewCalendar)
    }

    public func events(calendarID: String, window: ClosedRange<CalendarDate>) async throws -> [CalendarEventSnapshot] {
        guard let calendar = eventStore.calendar(withIdentifier: calendarID) else { throw CalendarStoreError() }
        return events(in: calendar, window: window).map { event in
            CalendarEventSnapshot(
                eventID: event.calendarItemIdentifier,
                taskID: TaskLink.taskID(in: event.url),
                title: event.title ?? "",
                notes: event.notes ?? "",
                day: CalendarDate(event.startDate, in: .current)
            )
        }
    }

    public func apply(_ changes: [CalendarChange], calendarID: String) async throws {
        guard let calendar = eventStore.calendar(withIdentifier: calendarID) else { throw CalendarStoreError() }
        do {
            for change in changes {
                switch change {
                case .create(let task):
                    let event = EKEvent(eventStore: eventStore)
                    event.calendar = calendar
                    fill(event, with: task)
                    try eventStore.save(event, span: .thisEvent, commit: false)
                case .update(let eventID, let task):
                    guard let event = ownEvent(eventID, calendarID: calendarID) else { continue }
                    fill(event, with: task)
                    try eventStore.save(event, span: .thisEvent, commit: false)
                case .delete(let eventID):
                    guard let event = ownEvent(eventID, calendarID: calendarID) else { continue }
                    try eventStore.remove(event, span: .thisEvent, commit: false)
                }
            }
            try eventStore.commit()
        } catch {
            eventStore.reset()
            throw error
        }
    }

    public func removeCalendar(id: String) async throws -> CalendarRemoval {
        guard let calendar = eventStore.calendar(withIdentifier: id) else { return .removed }
        var events: [String: EKEvent] = [:]
        for slice in CalendarRemoval.querySlices {
            // An event across two slices comes back twice; one entry per event.
            for event in self.events(in: calendar, window: slice) { events[event.calendarItemIdentifier] = event }
        }
        guard events.values.contains(where: { TaskLink.taskID(in: $0.url) == nil }) else {
            try eventStore.removeCalendar(calendar, commit: true)
            return .removed
        }
        do {
            for event in events.values where TaskLink.taskID(in: event.url) != nil {
                try eventStore.remove(event, span: .thisEvent, commit: false)
            }
            try eventStore.commit()
        } catch {
            eventStore.reset()
            throw error
        }
        return .keptForUserEvents
    }

    private func resetOnceAfterGrant() {
        guard !isFreshAfterGrant else { return }
        eventStore.reset()
        isFreshAfterGrant = true
    }

    /// An event of that calendar that carries a task link: the only kind the app changes or deletes.
    private func ownEvent(_ eventID: String, calendarID: String) -> EKEvent? {
        guard let event = eventStore.calendarItem(withIdentifier: eventID) as? EKEvent,
              event.calendar.calendarIdentifier == calendarID, TaskLink.taskID(in: event.url) != nil
        else { return nil }
        return event
    }

    /// A calendar titled `named` in the default source, held by no other workspace, with no event of the user's
    /// own (without a task link) in `window`.
    private func adoptableCalendar(
        named: String, excluding: Set<String>, window: ClosedRange<CalendarDate>
    ) -> EKCalendar? {
        guard let source = eventStore.defaultCalendarForNewEvents?.source else { return nil }
        return eventStore.calendars(for: .event).first { calendar in
            calendar.title == named && calendar.allowsContentModifications
                && calendar.source.sourceIdentifier == source.sourceIdentifier
                && !excluding.contains(calendar.calendarIdentifier)
                && events(in: calendar, window: window).allSatisfy { TaskLink.taskID(in: $0.url) != nil }
        }
    }

    private func events(in calendar: EKCalendar, window: ClosedRange<CalendarDate>) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(
            withStart: Self.startOfDay(window.lowerBound),
            end: Self.startOfDay(window.upperBound.adding(days: 1)),
            calendars: [calendar]
        )
        return eventStore.events(matching: predicate)
    }

    private func fill(_ event: EKEvent, with task: CalendarTask) {
        let start = Self.startOfDay(task.day)
        event.title = task.title
        event.notes = task.notes
        event.isAllDay = true
        event.startDate = start
        event.endDate = start
        event.url = TaskLink.url(for: task.id)
        event.alarms = Self.alarmOffsets.map { EKAlarm(relativeOffset: $0) }
    }

    /// Where a new calendar may go, in order: the default calendar's source (the user's own choice, whatever kind
    /// it is), the iCloud source, the local source. Never another CalDAV, Exchange or subscribed account: the
    /// task's text and sender must not land on a third party's server the user did not pick as default.
    private func candidateSources() -> [EKSource] {
        let iCloud = eventStore.sources.first { $0.sourceType == .calDAV && $0.title == "iCloud" }
        let local = eventStore.sources.first { $0.sourceType == .local }
        var sources: [EKSource] = []
        for source in [eventStore.defaultCalendarForNewEvents?.source, iCloud, local].compactMap({ $0 })
        where !sources.contains(where: { $0.sourceIdentifier == source.sourceIdentifier }) {
            sources.append(source)
        }
        return sources
    }

    /// 00:00 of `day` on this phone: the start of an all-day event.
    private static func startOfDay(_ day: CalendarDate) -> Date {
        Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
            ?? Date(timeIntervalSince1970: 0)
    }

    private static func access(_ status: EKAuthorizationStatus) -> CalendarAccess {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        case .denied, .restricted, .writeOnly: .denied
        @unknown default: .denied
        }
    }
}
