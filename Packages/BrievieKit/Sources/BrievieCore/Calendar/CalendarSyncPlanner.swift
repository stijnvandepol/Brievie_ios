import Foundation

/// Works out what a sync writes. Pure: the calendar is the state, matched on each event's task link.
public enum CalendarSyncPlanner {
    /// The most events a sync keeps in one workspace's calendar, the earliest deadlines first. Each has three
    /// alarms; a broken or hostile server that sends 100000 open tasks must not fill the user's calendar.
    public static let maxEvents = 250

    /// One year back to three years ahead, today included. The end stops 30 days short of three years so that the
    /// search EventKit runs (from the first day's start to the day after the last) stays clearly under the four
    /// years it searches at most.
    public static func window(today: CalendarDate) -> ClosedRange<CalendarDate> {
        today.adding(years: -1)...today.adding(years: 3).adding(days: -30)
    }

    /// - A task inside the window without an event is created; with an event that differs, updated.
    /// - An event of a task that is not among the tasks inside the window is deleted, and so is every event after
    ///   the first one of the same task.
    /// - An event without a task link (added by the user) is never touched.
    /// - Of the tasks inside the window only the `maxEvents` with the earliest deadlines count; the events of the
    ///   others are deleted.
    public static func plan(
        tasks: [CalendarTask], events: [CalendarEventSnapshot], window: ClosedRange<CalendarDate>
    ) -> [CalendarChange] {
        var wanted: [UUID: CalendarTask] = [:]
        for task in tasks where window.contains(task.day) && wanted[task.id] == nil {
            wanted[task.id] = task
        }
        if wanted.count > maxEvents {
            let kept = wanted.values.sorted { ($0.day, $0.id.uuidString) < ($1.day, $1.id.uuidString) }
                .prefix(maxEvents)
            wanted = Dictionary(uniqueKeysWithValues: kept.map { ($0.id, $0) })
        }
        var changes: [CalendarChange] = []
        var covered: Set<UUID> = []
        for event in events {
            guard let taskID = event.taskID else { continue }
            guard let task = wanted[taskID], !covered.contains(taskID) else {
                changes.append(.delete(eventID: event.eventID))
                continue
            }
            covered.insert(taskID)
            if event.title != task.title || event.notes != task.notes || event.day != task.day {
                changes.append(.update(eventID: event.eventID, task))
            }
        }
        for task in tasks where wanted[task.id] != nil && !covered.contains(task.id) {
            covered.insert(task.id)
            changes.append(.create(task))
        }
        return changes
    }
}
