@testable import BrievieCore
import Foundation
import Testing

/// "Verwijderen": the calendar goes only when it holds nothing of the user; otherwise only Brievie's events go.
@Suite struct CalendarRemovalTests {
    private static let today = CalendarDate(year: 2026, month: 11, day: 16)

    private let store = FakeCalendarStore()
    private let settings = InMemoryCalendarSettings()
    private let home = UUID()

    private func makeSync() -> CalendarSync {
        let task = WorkspaceTask(
            id: UUID(), type: "pay", description: "Factuur", deadline: Self.today, isDone: false, documentID: nil,
            sender: "Eneco"
        )
        return CalendarSync(
            store: store, settings: settings, tasks: { _ in [task] }, workspaceName: { _ in "Thuis" },
            typeTitle: { $0 }, today: { Self.today }
        )
    }

    /// The switch is on and the calendar holds one event of Brievie.
    private func enabled() async throws -> (CalendarSync, String) {
        let sync = makeSync()
        #expect(await sync.enable(workspace: home) == .done(created: 1, updated: 0, deleted: 0))
        return (sync, try #require(settings.calendarID(for: home)))
    }

    @Test func aCalendarWithOnlyBrieviesEventsIsRemoved() async throws {
        let (sync, id) = try await enabled()

        let removal = await sync.disable(workspace: home, removeCalendar: true)

        #expect(removal == .removed)
        #expect(await store.calendars[id] == nil)
        #expect(!settings.isEnabled(for: home))
    }

    @Test(arguments: [
        CalendarDate(year: 2000, month: 1, day: 1),
        CalendarDate(year: 2005, month: 6, day: 1),
        CalendarDate(year: 2100, month: 12, day: 31)
    ])
    func anEventOfTheUserAnywhereKeepsTheCalendar(day: CalendarDate) async throws {
        let (sync, id) = try await enabled()
        // Far outside the sync window: an adopted calendar the user had made with the same title.
        await store.userAddsEvent(title: "Verjaardag", day: day, calendarID: id)

        let removal = await sync.disable(workspace: home, removeCalendar: true)

        #expect(removal == .keptForUserEvents)
        #expect(await store.calendars[id] == "Brievie – Thuis")
        #expect(await store.storedEvents(calendarID: id).map(\.title) == ["Verjaardag"])
        #expect(!settings.isEnabled(for: home))
    }

    @Test func anEventOutsideTheCheckedYearsDoesNotCount() async throws {
        let (sync, id) = try await enabled()
        await store.userAddsEvent(title: "Oud", day: CalendarDate(year: 1999, month: 12, day: 31), calendarID: id)

        #expect(await sync.disable(workspace: home, removeCalendar: true) == .removed)
        #expect(await store.calendars[id] == nil)
    }

    @Test func keepingOrFailingRemovesNothing() async throws {
        let (sync, id) = try await enabled()
        #expect(await sync.disable(workspace: home, removeCalendar: false) == nil)
        #expect(await store.calendars[id] != nil)

        settings.enable(workspace: home, calendarID: id)
        await store.setFailing(true)
        #expect(await sync.disable(workspace: home, removeCalendar: true) == nil)
        #expect(!settings.isEnabled(for: home))
    }

    @Test func theCheckedYearsAreQueriedInSlicesEventKitAccepts() {
        let slices = CalendarRemoval.querySlices
        #expect(slices.first?.lowerBound == CalendarDate(year: 2000, month: 1, day: 1))
        #expect(slices.last?.upperBound == CalendarDate(year: 2100, month: 12, day: 31))
        for (earlier, later) in zip(slices, slices.dropFirst()) {
            #expect(earlier.upperBound.adding(days: 1) == later.lowerBound)
        }
        // EventKit searches at most four years at a time.
        #expect(slices.allSatisfy { $0.upperBound < CalendarDate(year: $0.lowerBound.year + 4, month: 1, day: 1) })
    }
}
