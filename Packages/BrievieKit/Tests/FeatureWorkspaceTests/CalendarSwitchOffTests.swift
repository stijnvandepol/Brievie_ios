@testable import BrievieCore
@testable import FeatureWorkspace
import Foundation
import Testing

/// Switching the calendar off with "Verwijderen" when the calendar also holds the user's own events.
@MainActor
@Suite struct CalendarSwitchOffTests {
    private let store = FakeCalendarStore()
    private let settings = InMemoryCalendarSettings()
    private let workspace = UUID()

    private func makeModel() -> CalendarSettingModel {
        let sync = CalendarSync(
            store: store, settings: settings, tasks: { _ in [] }, workspaceName: { _ in "Thuis" },
            typeTitle: { $0 }, today: { CalendarDate(year: 2026, month: 11, day: 16) }
        )
        return CalendarSettingModel(
            workspaceID: workspace, workspaceName: "Thuis", sync: sync, settings: settings, openSettings: {}
        )
    }

    @Test func aCalendarWithTheUsersEventsStaysAndTheSwitchSaysSo() async throws {
        let model = makeModel()
        model.toggle(true)
        await model.pendingTask?.value
        let id = try #require(settings.calendarID(for: workspace))
        await store.userAddsEvent(title: "Verjaardag", day: CalendarDate(year: 2010, month: 3, day: 4), calendarID: id)
        model.toggle(false)

        model.switchOff(removeCalendar: true)
        await model.pendingTask?.value

        #expect(!model.isOn)
        #expect(await store.calendars[id] != nil)
        #expect(model.message == WorkspaceStrings.calendarKeptForUserEvents)
        #expect(!model.showsOpenSettings)
        #expect(model.message == """
            In deze agenda staan ook afspraken van jou. De agenda blijft staan; de afspraken van Brievie zijn weg.
            """)

        // Switching on again drops the line.
        model.toggle(true)
        #expect(model.message == nil)
    }

    @Test func aRemovedCalendarSaysNothing() async throws {
        let model = makeModel()
        model.toggle(true)
        await model.pendingTask?.value
        model.toggle(false)

        model.switchOff(removeCalendar: true)
        await model.pendingTask?.value

        #expect(model.message == nil)
        #expect(await store.calendars.isEmpty)
    }

    @Test func voiceOverHearsWhichWorkspacesCalendarTheSwitchIsFor() {
        let model = makeModel()

        #expect(model.switchHint == model.footer)
        #expect(model.switchHint.contains("Brievie – Thuis"))
    }
}
