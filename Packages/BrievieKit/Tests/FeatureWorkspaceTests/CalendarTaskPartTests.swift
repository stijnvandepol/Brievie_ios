@testable import BrievieCore
@testable import FeatureWorkspace
import Foundation
import Testing

/// "Welke taken": the calendar gets the member's own tasks by default, or every task they may see.
@MainActor
@Suite struct CalendarTaskPartTests {
    private let store = FakeCalendarStore()
    private let settings = InMemoryCalendarSettings()
    private let workspace = UUID()

    private static func task(_ description: String) -> WorkspaceTask {
        WorkspaceTask(
            id: UUID(), type: "pay", description: description, deadline: CalendarDate(year: 2026, month: 12, day: 1),
            isDone: false, documentID: nil, sender: "Eneco"
        )
    }

    private func makeModel() -> CalendarSettingModel {
        let own = Self.task("Mijn factuur")
        let other = Self.task("Factuur van Anne")
        let settings = settings
        // As the app does: the calendar's task source follows the stored choice.
        let sync = CalendarSync(
            store: store, settings: settings,
            tasks: { workspace in settings.taskPart(for: workspace) == .all ? [own, other] : [own] },
            workspaceName: { _ in "Thuis" }, typeTitle: { _ in "Betalen" },
            today: { CalendarDate(year: 2026, month: 11, day: 16) }
        )
        return CalendarSettingModel(
            workspaceID: workspace, workspaceName: "Thuis", sync: sync, settings: settings, openSettings: {}
        )
    }

    private func eventCount() async throws -> Int {
        await store.storedEvents(calendarID: try #require(settings.calendarID(for: workspace))).count
    }

    @Test func mineIsTheDefault() {
        #expect(makeModel().taskPart == .mine)
    }

    @Test func switchingToAllTasksSyncsOnce() async throws {
        let model = makeModel()
        model.toggle(true)
        await model.pendingTask?.value
        #expect(try await eventCount() == 1)

        model.setTaskPart(.all)
        await model.pendingTask?.value

        #expect(settings.taskPart(for: workspace) == .all)
        #expect(try await eventCount() == 2)

        model.setTaskPart(.mine)
        await model.pendingTask?.value

        #expect(try await eventCount() == 1)
    }

    @Test func switchingWhileOffOnlyStores() {
        let model = makeModel()

        model.setTaskPart(.all)

        #expect(model.taskPart == .all)
        #expect(settings.taskPart(for: workspace) == .all)
        #expect(model.pendingTask == nil)
        #expect(makeModel().taskPart == .all)
    }

    @Test func toPickUpIsNeverAChoice() {
        let model = makeModel()

        model.setTaskPart(.toPickUp)

        #expect(model.taskPart == .mine)
    }
}
