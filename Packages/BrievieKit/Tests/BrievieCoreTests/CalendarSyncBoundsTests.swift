@testable import BrievieCore
import Foundation
import Testing

/// A broken or hostile server can send any number of open tasks; the user's calendar gets at most
/// `CalendarSyncPlanner.maxEvents` of them, the earliest deadlines first.
@Suite struct CalendarSyncBoundsTests {
    private static let today = CalendarDate(year: 2026, month: 11, day: 16)
    private let window = CalendarSyncPlanner.window(today: CalendarSyncBoundsTests.today)

    private func task(day: CalendarDate) -> CalendarTask {
        CalendarTask(id: UUID(), title: "Betalen (Brievie)", notes: "Uit Brievie", day: day)
    }

    @Test func manyTasksMakeAtMostTheMaximumOfEventsTheEarliestFirst() {
        let count = CalendarSyncPlanner.maxEvents + 50
        // Latest deadline first, so a plain prefix of the list would keep the wrong ones.
        let tasks = (0..<count).reversed().map { task(day: Self.today.adding(days: $0)) }

        let changes = CalendarSyncPlanner.plan(tasks: tasks, events: [], window: window)

        let created = changes.compactMap { change -> CalendarDate? in
            if case .create(let task) = change { return task.day }
            return nil
        }
        #expect(created.count == CalendarSyncPlanner.maxEvents)
        #expect(created.max() == Self.today.adding(days: CalendarSyncPlanner.maxEvents - 1))
    }

    @Test func anEventOfATaskBeyondTheMaximumIsDeleted() {
        let tasks = (0..<(CalendarSyncPlanner.maxEvents + 1)).map { task(day: Self.today.adding(days: $0)) }
        let last = tasks[tasks.count - 1]
        let event = CalendarEventSnapshot(
            eventID: "last", taskID: last.id, title: last.title, notes: last.notes, day: last.day
        )

        let changes = CalendarSyncPlanner.plan(tasks: tasks, events: [event], window: window)

        #expect(changes.contains(.delete(eventID: "last")))
        #expect(!changes.contains { if case .create(let task) = $0 { task.id == last.id } else { false } })
    }

    @Test func theMaximumIsANamedSmallNumber() {
        // Three alarms per event: the cap keeps the alarms in the user's calendar in the hundreds.
        #expect(CalendarSyncPlanner.maxEvents > 0)
        #expect(CalendarSyncPlanner.maxEvents <= 500)
    }
}
