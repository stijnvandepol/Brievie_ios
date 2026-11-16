import EventKit
import Foundation

/// `CalendarStore` over EventKit. One `EKEventStore`, used only inside this actor.
///
/// Events are all-day, on the deadline, with the task link as their URL and three alarms at 09:00 local time:
/// 7 days before, 2 days before and on the day. Never used by the unit tests (they must not ask for access).
public actor EventKitCalendarStore: CalendarStore {
    /// Seconds from the start of the all-day event (00:00 on the deadline).
    private static let alarmOffsets: [TimeInterval] = [-7 * 86_400 + 9 * 3_600, -2 * 86_400 + 9 * 3_600, 9 * 3_600]

    private let eventStore = EKEventStore()

    public init() {}

    public func access() async -> CalendarAccess {
        Self.access(EKEventStore.authorizationStatus(for: .event))
    }

    public func requestAccess() async -> CalendarAccess {
        do {
            return try await eventStore.requestFullAccessToEvents() ? .granted : .denied
        } catch {
            return .denied
        }
    }

    public func ensureCalendar(named: String, existingID: String?) async throws -> String {
        if let existingID, let calendar = eventStore.calendar(withIdentifier: existingID),
           calendar.allowsContentModifications {
            return existingID
        }
        if let match = eventStore.calendars(for: .event).first(where: {
            $0.title == named && $0.allowsContentModifications
        }) {
            return match.calendarIdentifier
        }
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = named
        // The phone's default calendar source (usually iCloud); the local one when that one takes no new calendar.
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
        throw lastError ?? CalendarStoreError()
    }

    public func events(calendarID: String, window: ClosedRange<CalendarDate>) async throws -> [CalendarEventSnapshot] {
        guard let calendar = eventStore.calendar(withIdentifier: calendarID) else { throw CalendarStoreError() }
        let predicate = eventStore.predicateForEvents(
            withStart: Self.startOfDay(window.lowerBound),
            end: Self.startOfDay(window.upperBound.adding(days: 1)),
            calendars: [calendar]
        )
        return eventStore.events(matching: predicate).map { event in
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
                    guard let event = eventStore.calendarItem(withIdentifier: eventID) as? EKEvent,
                          event.calendar.calendarIdentifier == calendarID
                    else { continue }
                    fill(event, with: task)
                    try eventStore.save(event, span: .thisEvent, commit: false)
                case .delete(let eventID):
                    guard let event = eventStore.calendarItem(withIdentifier: eventID) as? EKEvent,
                          event.calendar.calendarIdentifier == calendarID
                    else { continue }
                    try eventStore.remove(event, span: .thisEvent, commit: false)
                }
            }
            try eventStore.commit()
        } catch {
            eventStore.reset()
            throw error
        }
    }

    public func removeCalendar(id: String) async throws {
        guard let calendar = eventStore.calendar(withIdentifier: id) else { return }
        try eventStore.removeCalendar(calendar, commit: true)
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

    private func candidateSources() -> [EKSource] {
        var sources: [EKSource] = []
        if let source = eventStore.defaultCalendarForNewEvents?.source { sources.append(source) }
        if let local = eventStore.sources.first(where: { $0.sourceType == .local }),
           !sources.contains(where: { $0.sourceIdentifier == local.sourceIdentifier }) {
            sources.append(local)
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
