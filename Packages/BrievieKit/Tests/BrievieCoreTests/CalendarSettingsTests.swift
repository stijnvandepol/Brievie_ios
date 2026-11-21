@testable import BrievieCore
import BrievieScan
import Foundation
import Testing

/// The calendar switch per workspace, stored in `UserDefaults`, and what unpairing does with it.
@Suite struct CalendarSettingsTests {
    private let suiteName = "calendar-settings-\(UUID().uuidString)"

    @Test func aWorkspaceIsOffUntilEnabled() {
        let settings = UserDefaultsCalendarSettings(suiteName: suiteName)
        let workspace = UUID()

        #expect(!settings.isEnabled(for: workspace))
        #expect(settings.calendarID(for: workspace) == nil)

        settings.enable(workspace: workspace, calendarID: "calendar-1")

        #expect(settings.isEnabled(for: workspace))
        #expect(settings.calendarID(for: workspace) == "calendar-1")
        #expect(UserDefaults(suiteName: suiteName)?.string(forKey: "calendar.\(workspace.uuidString)") == "calendar-1")
    }

    @Test func calendarIDsListsTheWorkspacesThatAreOn() {
        let settings = UserDefaultsCalendarSettings(suiteName: suiteName)
        UserDefaults(suiteName: suiteName)?.set(true, forKey: "hasLaunchedBefore")
        let home = UUID()
        let business = UUID()
        settings.enable(workspace: home, calendarID: "a")
        settings.enable(workspace: business, calendarID: "b")
        settings.disable(workspace: business)

        #expect(settings.calendarIDs() == [home: "a"])
    }

    @Test func disableTurnsOnlyThatWorkspaceOff() {
        let settings = UserDefaultsCalendarSettings(suiteName: suiteName)
        let home = UUID()
        let business = UUID()
        settings.enable(workspace: home, calendarID: "a")
        settings.enable(workspace: business, calendarID: "b")

        settings.disable(workspace: home)

        #expect(!settings.isEnabled(for: home))
        #expect(settings.calendarID(for: business) == "b")
    }

    @Test func removeAllClearsEveryWorkspaceAndNothingElse() {
        let settings = UserDefaultsCalendarSettings(suiteName: suiteName)
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.set(true, forKey: "hasLaunchedBefore")
        let home = UUID()
        let business = UUID()
        settings.enable(workspace: home, calendarID: "a")
        settings.enable(workspace: business, calendarID: "b")

        settings.removeAll()

        #expect(!settings.isEnabled(for: home))
        #expect(!settings.isEnabled(for: business))
        #expect(defaults?.bool(forKey: "hasLaunchedBefore") == true)
    }

    @Test func unpairClearsTheSettingsAndKeepsCalendars() async throws {
        let settings = InMemoryCalendarSettings()
        let store = FakeCalendarStore()
        let workspace = UUID()
        let sync = CalendarSync(
            store: store, settings: settings, tasks: { _ in [] }, workspaceName: { _ in "Thuis" },
            typeTitle: { $0 }, today: { CalendarDate(year: 2026, month: 11, day: 16) }
        )
        _ = await sync.enable(workspace: workspace)
        let calendarID = try #require(settings.calendarID(for: workspace))
        let unpairing = Unpairing(
            server: try FakeBrievieServer(), uploads: EmptyUploadQueue(), calendarSettings: settings
        )

        try await unpairing.wipeLocalState()

        #expect(!settings.isEnabled(for: workspace))
        #expect(await store.calendars == [calendarID: "Brievie – Thuis"])
    }

    @Test func taskPartDefaultsToMineAndIsStoredPerWorkspace() {
        let settings = UserDefaultsCalendarSettings(suiteName: suiteName)
        let home = UUID()
        let business = UUID()
        #expect(settings.taskPart(for: home) == .mine)

        settings.setTaskPart(.all, for: business)

        #expect(settings.taskPart(for: business) == .all)
        #expect(settings.taskPart(for: home) == .mine)
        settings.setTaskPart(.mine, for: business)
        #expect(UserDefaults(suiteName: suiteName)?.object(forKey: "calendarTasks.\(business.uuidString)") == nil)
    }

    @Test func taskPartIsForgottenWithThePairing() {
        let settings = UserDefaultsCalendarSettings(suiteName: suiteName)
        let memory = InMemoryCalendarSettings()
        let workspace = UUID()
        settings.setTaskPart(.all, for: workspace)
        memory.setTaskPart(.all, for: workspace)

        settings.removeAll()
        memory.removeAll()

        #expect(settings.taskPart(for: workspace) == .mine)
        #expect(memory.taskPart(for: workspace) == .mine)
    }
}

/// An upload queue with nothing in it (also used by `AppModelUnpairCalendarTests`).
struct EmptyUploadQueue: UploadQueue {
    func enqueue(pages: [ScannedPage], workspaceID: UUID) async throws(UploadQueueError) -> UploadItem {
        throw UploadQueueError.writeFailed
    }

    func items() async -> [UploadItem] { [] }
    func retry(_ id: UUID) async {}
    func delete(_ id: UUID) async {}
    func removeAll() async throws {}
    func progressUpdates() async -> AsyncStream<[UUID: Double]> { AsyncStream { $0.finish() } }
    func takeRemovedUnreadableCount() async -> Int { 0 }
}
