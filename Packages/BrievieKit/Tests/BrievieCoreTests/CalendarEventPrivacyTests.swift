@testable import BrievieCore
import Foundation
import Testing

/// What an event shows. Its title appears on the lock screen and in widgets (three alarms), outside the app
/// lock, and other apps with calendar access read it: by default only the task type and the app's name.
@Suite struct CalendarEventPrivacyTests {
    private static let today = CalendarDate(year: 2026, month: 11, day: 17)

    private let store = FakeCalendarStore()
    private let settings = InMemoryCalendarSettings()
    private let home = UUID()
    private let task = WorkspaceTask(
        id: UUID(), type: "pay", description: "Betaal € 1.234,56 aan het CJIB", deadline: today, isDone: false,
        documentID: nil, sender: "CJIB"
    )

    private func makeSync() -> CalendarSync {
        let task = task
        return CalendarSync(
            store: store, settings: settings, tasks: { _ in [task] }, workspaceName: { _ in "Thuis" },
            typeTitle: { $0 == "pay" ? "Betalen" : "Overig" }, today: { Self.today }
        )
    }

    private func events() async throws -> [CalendarEventSnapshot] {
        await store.storedEvents(calendarID: try #require(settings.calendarID(for: home)))
    }

    @Test func byDefaultAnEventShowsOnlyTheTaskTypeAndTheAppName() throws {
        let event = try #require(CalendarTask.from(task, typeTitle: { _ in "Betalen" }))

        #expect(event.title == "Betalen (Brievie)")
        #expect(event.notes == "Uit Brievie")
        #expect(!event.title.contains("CJIB") && !event.notes.contains("CJIB"))
        #expect(!event.title.contains("1.234"))
    }

    @Test func withTheDescriptionSwitchOnTheEventHasDescriptionAndSender() throws {
        let event = try #require(CalendarTask.from(task, typeTitle: { _ in "Betalen" }, showsDetails: true))

        #expect(event.title == "Betalen: Betaal € 1.234,56 aan het CJIB")
        #expect(event.notes == "CJIB\nUit Brievie")
    }

    @Test func aSyncWritesNeutralEventsByDefault() async throws {
        _ = await makeSync().enable(workspace: home)

        let event = try #require(try await events().first)
        #expect(event.title == "Betalen (Brievie)")
        #expect(event.notes == "Uit Brievie")
        #expect(event.taskID == task.id, "The task link stays, so the app finds its own events")
    }

    @Test func turningTheDescriptionOnAndOffRewritesTheEventsOnTheNextSync() async throws {
        let sync = makeSync()
        _ = await sync.enable(workspace: home)

        settings.setShowsDetails(true, for: home)
        #expect(await sync.sync(workspace: home) == .done(created: 0, updated: 1, deleted: 0))
        #expect(try await events().map(\.title) == ["Betalen: Betaal € 1.234,56 aan het CJIB"])

        settings.setShowsDetails(false, for: home)
        #expect(await sync.sync(workspace: home) == .done(created: 0, updated: 1, deleted: 0))
        #expect(try await events().map(\.title) == ["Betalen (Brievie)"])
    }

    @Test func anEventFromBeforeThisChangeIsRewrittenToTheNeutralForm() async throws {
        let sync = makeSync()
        _ = await sync.enable(workspace: home)
        let id = try #require(settings.calendarID(for: home))
        let event = try #require(try await events().first)
        // As an older version wrote it.
        try await store.apply(
            [.update(eventID: event.eventID, CalendarTask(
                id: task.id, title: "Betalen: Betaal € 1.234,56 aan het CJIB", notes: "CJIB\nUit Brievie",
                day: Self.today
            ))],
            calendarID: id
        )

        #expect(await sync.sync(workspace: home) == .done(created: 0, updated: 1, deleted: 0))
        #expect(try await events().map(\.title) == ["Betalen (Brievie)"])
    }

    @Test func theDescriptionChoiceIsForgottenWithThePairing() {
        settings.setShowsDetails(true, for: home)

        settings.removeAll()

        #expect(!settings.showsDetails(for: home))
    }

    @Test func theUserDefaultsSettingsKeepTheDescriptionChoice() {
        let settings = UserDefaultsCalendarSettings(suiteName: "calendar-details-\(UUID().uuidString)")
        #expect(!settings.showsDetails(for: home))

        settings.setShowsDetails(true, for: home)
        #expect(settings.showsDetails(for: home))

        settings.removeAll()
        #expect(!settings.showsDetails(for: home))
    }

    @Test func catalogAndCodeAgree() throws {
        #expect(
            try CatalogParity.dutchValue(forKey: "calendar.event.neutralTitle", target: "BrievieCore")
                == AppStrings.calendarNeutralTitleFormat
        )
    }
}
