@testable import BrievieCore
import Foundation
import Testing

/// Choosing or making a workspace's calendar is one step across all workspaces, and never outlives an unpair.
@Suite struct CalendarChoiceTests {
    private static let today = CalendarDate(year: 2026, month: 11, day: 17)

    private let store = FakeCalendarStore()
    private let settings = InMemoryCalendarSettings()

    private func makeSync(tasks: @escaping CalendarSync.TaskSource = { _ in [] }) -> CalendarSync {
        CalendarSync(
            store: store, settings: settings,
            tasks: { workspace in
                await Task.yield()
                return try await tasks(workspace)
            },
            workspaceName: { _ in "Thuis" }, typeTitle: { $0 }, today: { Self.today }
        )
    }

    @Test(arguments: 0..<20)
    func twoWorkspacesWithTheSameNameSwitchedOnAtOnceGetTwoCalendars(round: Int) async throws {
        let sync = makeSync()
        let workspaces = (0..<3).map { _ in UUID() }

        await withTaskGroup(of: Void.self) { group in
            for workspace in workspaces {
                group.addTask { _ = await sync.enable(workspace: workspace) }
            }
        }

        let ids = workspaces.compactMap { settings.calendarID(for: $0) }
        #expect(ids.count == 3)
        #expect(Set(ids).count == 3)
        #expect(await store.calendars.count == 3)
    }

    @Test(arguments: 0..<20)
    func calendarsMadeAgainAtOnceAreTwoToo(round: Int) async throws {
        let sync = makeSync()
        let (home, other) = (UUID(), UUID())
        _ = await sync.enable(workspace: home)
        _ = await sync.enable(workspace: other)
        // The user deleted both calendars: the next syncs make them again, at the same moment.
        for id in settings.calendarIDs().values { await store.userDeletesCalendar(id: id) }

        async let first = sync.sync(workspace: home)
        async let second = sync.sync(workspace: other)
        _ = await (first, second)

        let ids = [home, other].compactMap { settings.calendarID(for: $0) }
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
    }

    @Test func unpairingWhileSwitchingOnLeavesNoSetting() async throws {
        let settings = settings
        // The pairing is forgotten while the switch reads the tasks from the server.
        let sync = makeSync { _ in
            settings.removeAll()
            return []
        }

        let result = await sync.enable(workspace: UUID())

        #expect(result == .off)
        #expect(settings.calendarIDs().isEmpty)
    }

    @Test func aClearAfterTheGenerationWasReadRefusesTheStore() {
        let workspace = UUID()
        let generation = settings.clearGeneration()

        settings.removeAll()

        #expect(!settings.enable(workspace: workspace, calendarID: "a", ifGeneration: generation))
        #expect(settings.enable(workspace: workspace, calendarID: "a", ifGeneration: settings.clearGeneration()))
        #expect(settings.calendarID(for: workspace) == "a")
    }

    @Test func theUserDefaultsSettingsCountTheirClearsToo() {
        let settings = UserDefaultsCalendarSettings(suiteName: "calendar-choice-\(UUID().uuidString)")
        let workspace = UUID()
        let generation = settings.clearGeneration()

        settings.removeAll()

        #expect(!settings.enable(workspace: workspace, calendarID: "a", ifGeneration: generation))
        #expect(!settings.isEnabled(for: workspace))
    }

    @Test func eachDefaultsSuiteCountsItsOwnClears() {
        let one = UserDefaultsCalendarSettings(suiteName: "calendar-choice-\(UUID().uuidString)")
        let other = UserDefaultsCalendarSettings(suiteName: "calendar-choice-\(UUID().uuidString)")
        let generation = one.clearGeneration()

        other.removeAll()

        #expect(one.clearGeneration() == generation)
        #expect(one.enable(workspace: UUID(), calendarID: "a", ifGeneration: generation))
    }
}
