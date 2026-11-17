@testable import BrievieCore
import Foundation
import Testing

/// The pure part of the calendar sync: which events to create, update and delete.
@Suite struct CalendarSyncPlannerTests {
    private static let today = CalendarDate(year: 2026, month: 11, day: 16)
    private let window = CalendarSyncPlanner.window(today: CalendarSyncPlannerTests.today)

    private func task(_ id: UUID = UUID(), title: String = "Betalen: Factuur", day: CalendarDate = today)
        -> CalendarTask {
        CalendarTask(id: id, title: title, notes: "Eneco\nUit Brievie", day: day)
    }

    private func event(_ eventID: String, for task: CalendarTask) -> CalendarEventSnapshot {
        CalendarEventSnapshot(eventID: eventID, taskID: task.id, title: task.title, notes: task.notes, day: task.day)
    }

    @Test func planCreatesEventsForNewTasks() {
        let first = task()
        let second = task(day: CalendarDate(year: 2027, month: 2, day: 1))

        let changes = CalendarSyncPlanner.plan(tasks: [first, second], events: [], window: window)

        #expect(changes == [.create(first), .create(second)])
    }

    @Test func planUpdatesAChangedDeadlineOrText() {
        let moved = task()
        let renamed = task()
        let events = [
            event("a", for: CalendarTask(id: moved.id, title: moved.title, notes: moved.notes, day: CalendarDate(
                year: 2026, month: 11, day: 30
            ))),
            event("b", for: CalendarTask(id: renamed.id, title: "Oud", notes: renamed.notes, day: renamed.day))
        ]

        let changes = CalendarSyncPlanner.plan(tasks: [moved, renamed], events: events, window: window)

        #expect(changes == [.update(eventID: "a", moved), .update(eventID: "b", renamed)])
    }

    @Test func planDeletesEventsOfDoneOrVanishedTasks() {
        let open = task()
        let gone = task()
        let events = [event("open", for: open), event("gone", for: gone)]

        let changes = CalendarSyncPlanner.plan(tasks: [open], events: events, window: window)

        #expect(changes == [.delete(eventID: "gone")])
    }

    @Test func planLeavesEventsWithoutABrievieURLAlone() {
        let ownEvent = CalendarEventSnapshot(
            eventID: "own", taskID: nil, title: "Verjaardag", notes: "", day: Self.today
        )

        #expect(CalendarSyncPlanner.plan(tasks: [], events: [ownEvent], window: window).isEmpty)
    }

    @Test func planRemovesDuplicateEventsOfOneTask() {
        let open = task()
        let events = [event("first", for: open), event("second", for: open), event("third", for: open)]

        let changes = CalendarSyncPlanner.plan(tasks: [open], events: events, window: window)

        #expect(changes == [.delete(eventID: "second"), .delete(eventID: "third")])
    }

    @Test func planIgnoresTasksOutsideTheWindow() {
        let farAway = task(day: CalendarDate(year: 2030, month: 11, day: 16))
        let longAgo = task(day: CalendarDate(year: 2025, month: 11, day: 15))
        // The task's event still sits on its old date inside the window; the deadline moved out of it.
        let moved = task(day: CalendarDate(year: 2031, month: 1, day: 1))
        let staleEvent = event("stale", for: CalendarTask(
            id: moved.id, title: moved.title, notes: moved.notes, day: Self.today
        ))

        let changes = CalendarSyncPlanner.plan(tasks: [farAway, longAgo, moved], events: [staleEvent], window: window)

        #expect(changes == [.delete(eventID: "stale")])
    }

    @Test func planIsEmptyWhenEverythingMatches() {
        let first = task()
        let second = task(day: CalendarDate(year: 2028, month: 3, day: 3))
        let events = [event("1", for: first), event("2", for: second)]

        #expect(CalendarSyncPlanner.plan(tasks: [first, second], events: events, window: window).isEmpty)
    }

    @Test func aTaskListedTwiceGetsOneEvent() {
        let open = task()

        #expect(CalendarSyncPlanner.plan(tasks: [open, open], events: [], window: window) == [.create(open)])
    }

    // MARK: - The window

    @Test func theWindowRunsFromOneYearBackTo30DaysBeforeThreeYearsAhead() {
        #expect(window.lowerBound == CalendarDate(year: 2025, month: 11, day: 16))
        #expect(window.upperBound == CalendarDate(year: 2029, month: 10, day: 17))
    }

    @Test func aLeapDayWindowEndsOnTheLastDayOfFebruary() {
        let window = CalendarSyncPlanner.window(today: CalendarDate(year: 2028, month: 2, day: 29))

        #expect(window.lowerBound == CalendarDate(year: 2027, month: 2, day: 28))
        #expect(window.upperBound == CalendarDate(year: 2031, month: 1, day: 29))
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDate {
        CalendarDate(year: year, month: month, day: day)
    }

    @Test func addingDaysCrossesMonthsAndYears() {
        #expect(Self.day(2026, 1, 1).adding(days: -1) == Self.day(2025, 12, 31))
        #expect(Self.day(2024, 2, 28).adding(days: 1) == Self.day(2024, 2, 29))
        #expect(Self.day(2023, 2, 28).adding(days: 1) == Self.day(2023, 3, 1))
        #expect(Self.day(2026, 3, 1).adding(days: -1) == Self.day(2026, 2, 28))
        #expect(Self.day(2026, 12, 30).adding(days: 40) == Self.day(2027, 2, 8))
        #expect(Self.day(2027, 2, 8).adding(days: -40) == Self.day(2026, 12, 30))
        #expect(Self.day(2026, 11, 16).adding(days: 0) == Self.day(2026, 11, 16))
    }

    @Test func addingYearsKeepsTheDayUnlessItDoesNotExist() {
        #expect(Self.day(2026, 5, 31).adding(years: 3) == Self.day(2029, 5, 31))
        #expect(Self.day(2024, 2, 29).adding(years: 1) == Self.day(2025, 2, 28))
        #expect(Self.day(2024, 2, 29).adding(years: 4) == Self.day(2028, 2, 29))
        #expect(Self.day(2024, 2, 29).adding(years: 76) == Self.day(2100, 2, 28))
        #expect(Self.day(2004, 2, 29).adding(years: -4) == Self.day(2000, 2, 29))
    }

    // MARK: - From a workspace task

    private func workspaceTask(deadline: CalendarDate?, isDone: Bool = false, sender: String = "Eneco")
        -> WorkspaceTask {
        WorkspaceTask(
            id: UUID(), type: "pay", description: "Factuur november", deadline: deadline, isDone: isDone,
            documentID: UUID(), sender: sender
        )
    }

    @Test func anOpenTaskWithADeadlineGivesTitleAndNotesWithDetails() throws {
        let source = workspaceTask(deadline: Self.today)

        let task = try #require(CalendarTask.from(
            source, typeTitle: { $0 == "pay" ? "Betalen" : "?" }, showsDetails: true
        ))

        #expect(task == CalendarTask(
            id: source.id, title: "Betalen: Factuur november", notes: "Eneco\nUit Brievie", day: Self.today
        ))
    }

    @Test func withoutASenderTheNotesOnlySayWhereItCameFrom() {
        let task = CalendarTask.from(
            workspaceTask(deadline: Self.today, sender: "  "), typeTitle: { _ in "Betalen" }, showsDetails: true
        )

        #expect(task?.notes == "Uit Brievie")
    }

    @Test func doneTaskOrTaskWithoutDeadlineGivesNoCalendarTask() {
        #expect(CalendarTask.from(workspaceTask(deadline: nil), typeTitle: { $0 }) == nil)
        #expect(CalendarTask.from(workspaceTask(deadline: Self.today, isDone: true), typeTitle: { $0 }) == nil)
    }

    // MARK: - The link in an event

    @Test func theTaskLinkRoundTripsAndOtherURLsHaveNoTask() throws {
        let id = UUID()
        let url = try #require(TaskLink.url(for: id))

        #expect(url.absoluteString == "brievie://task/\(id.uuidString.lowercased())")
        #expect(TaskLink.taskID(in: url) == id)
        #expect(TaskLink.taskID(in: URL(string: "brievie://task/\(id.uuidString)")) == id)
        #expect(TaskLink.taskID(in: URL(string: "https://task/\(id.uuidString)")) == nil)
        #expect(TaskLink.taskID(in: URL(string: "brievie://document/\(id.uuidString)")) == nil)
        #expect(TaskLink.taskID(in: URL(string: "brievie://task/not-a-uuid")) == nil)
        #expect(TaskLink.taskID(in: nil) == nil)
    }

    @Test func catalogAndCodeAgree() throws {
        let expected = [
            ("calendar.notes.footer", AppStrings.calendarNotesFooter),
            ("calendar.name", AppStrings.calendarNameFormat)
        ]
        for (key, resolved) in expected {
            #expect(try CatalogParity.dutchValue(forKey: key, target: "BrievieCore") == resolved, "\(key)")
        }
    }
}
