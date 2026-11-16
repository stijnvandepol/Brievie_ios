@testable import BrievieCore
import Foundation
import Testing

/// `CalendarSync` against a server whose task list fails or a workspace that was renamed.
@Suite struct CalendarSyncServerTests {
    private static let today = CalendarDate(year: 2026, month: 11, day: 16)

    private let store = FakeCalendarStore()
    private let settings = InMemoryCalendarSettings()
    private let home = UUID()

    private func calendarID(_ workspace: UUID) throws -> String {
        try #require(settings.calendarID(for: workspace))
    }

    @Test func aServerWithoutATaskListGetsNoCalendar() async {
        let sync = CalendarSync(
            store: store, settings: settings, tasks: { _ in throw DocumentsError.notSupported },
            workspaceName: { _ in "Thuis" }, typeTitle: { $0 }, today: { Self.today }
        )

        #expect(await sync.enable(workspace: home) == .tasksNotSupported)
        #expect(!settings.isEnabled(for: home))
        #expect(await store.calendars.isEmpty)
    }

    @Test func aServerWithoutATaskListIsToldBeforeTheAccessPrompt() async {
        await store.setAccess(.notDetermined, grantsOnRequest: true)
        let sync = CalendarSync(
            store: store, settings: settings, tasks: { _ in throw DocumentsError.notSupported },
            workspaceName: { _ in "Thuis" }, typeTitle: { $0 }, today: { Self.today }
        )

        #expect(await sync.enable(workspace: home) == .tasksNotSupported)
        #expect(await store.accessRequests == 0)
    }

    @Test func aFirstFillThatFailsOtherwiseStillMakesTheCalendar() async {
        let sync = CalendarSync(
            store: store, settings: settings, tasks: { _ in throw DocumentsError.unreachable },
            workspaceName: { _ in "Thuis" }, typeTitle: { $0 }, today: { Self.today }
        )

        #expect(await sync.enable(workspace: home) == .failed)
        #expect(settings.isEnabled(for: home), "The next sync fills it")
        #expect(await store.calendars.count == 1)
    }

    @Test func aRenamedWorkspaceRenamesItsCalendar() async throws {
        let name = Locked("Thuis")
        let sync = CalendarSync(
            store: store, settings: settings, tasks: { _ in [] }, workspaceName: { _ in name.value },
            typeTitle: { $0 }, today: { Self.today }
        )
        _ = await sync.enable(workspace: home)
        let id = try calendarID(home)

        name.value = "Huis"
        _ = await sync.sync(workspace: home)

        #expect(try calendarID(home) == id)
        #expect(await store.calendars == [id: "Brievie – Huis"])
    }
}
