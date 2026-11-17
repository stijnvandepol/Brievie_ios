@testable import BrievieCore
import Foundation
import Testing

/// `CalendarSync` against the in-memory calendar store: the switch, access, the calendar per workspace.
@Suite struct CalendarSyncTests {
    private static let today = CalendarDate(year: 2026, month: 11, day: 16)

    private let store = FakeCalendarStore()
    private let settings = InMemoryCalendarSettings()
    private let tasks = Locked<[UUID: [WorkspaceTask]]>([:])
    private let home = UUID()
    private let business = UUID()

    private func makeSync(names: [UUID: String]? = nil) -> CalendarSync {
        let tasks = tasks
        let names = names ?? [home: "Thuis", business: "Zaak"]
        return CalendarSync(
            store: store,
            settings: settings,
            tasks: { workspace in
                await Task.yield()
                return tasks.value[workspace] ?? []
            },
            workspaceName: { names[$0] ?? "" },
            typeTitle: { $0 == "pay" ? "Betalen" : "Overig" },
            today: { Self.today }
        )
    }

    private func openTask(_ description: String = "Factuur", deadline: CalendarDate = today) -> WorkspaceTask {
        WorkspaceTask(
            id: UUID(), type: "pay", description: description, deadline: deadline, isDone: false, documentID: nil,
            sender: "Eneco"
        )
    }

    private func calendarID(_ workspace: UUID) throws -> String {
        try #require(settings.calendarID(for: workspace))
    }

    @Test func syncDoesNothingWhenSwitchedOff() async {
        tasks.value = [home: [openTask()]]

        let result = await makeSync().sync(workspace: home)

        #expect(result == .off)
        #expect(await store.calendars.isEmpty)
        #expect(await store.accessChecks == 0)
    }

    @Test func syncWithoutAccessReportsNoAccessAndWritesNothing() async {
        tasks.value = [home: [openTask()]]
        await store.setAccess(.denied, grantsOnRequest: false)
        let sync = makeSync()

        #expect(await sync.enable(workspace: home) == .noAccess)
        #expect(!settings.isEnabled(for: home))

        // Access was taken away after the switch was turned on.
        settings.enable(workspace: home, calendarID: "earlier")
        #expect(await sync.sync(workspace: home) == .noAccess)
        #expect(await store.calendars.isEmpty)
        #expect(await store.appliedChanges.isEmpty)
    }

    @Test func enableAsksForAccessMakesTheCalendarAndFillsIt() async throws {
        tasks.value = [home: [openTask(), openTask("Aanslag")]]
        await store.setAccess(.notDetermined, grantsOnRequest: true)

        let result = await makeSync().enable(workspace: home)

        #expect(result == .done(created: 2, updated: 0, deleted: 0))
        #expect(await store.accessRequests == 1)
        let id = try calendarID(home)
        #expect(await store.calendars == [id: "Brievie – Thuis"])
        let titles = await store.storedEvents(calendarID: id).map(\.title)
        #expect(titles.sorted() == ["Betalen: Aanslag", "Betalen: Factuur"])
    }

    @Test func aSecondSyncUpdatesAndDeletes() async throws {
        let moved = openTask()
        let done = openTask("Klaar")
        tasks.value = [home: [moved, done]]
        let sync = makeSync()
        _ = await sync.enable(workspace: home)
        let later = CalendarDate(year: 2026, month: 12, day: 1)
        tasks.value = [home: [WorkspaceTask(
            id: moved.id, type: moved.type, description: moved.description, deadline: later, isDone: false,
            documentID: nil, sender: moved.sender
        )]]

        let result = await sync.sync(workspace: home)

        #expect(result == .done(created: 0, updated: 1, deleted: 1))
        let events = await store.storedEvents(calendarID: try calendarID(home))
        #expect(events.map(\.day) == [later])
        #expect(events.map(\.taskID) == [moved.id])
    }

    @Test func aFailingStoreReportsFailed() async {
        tasks.value = [home: [openTask()]]
        let sync = makeSync()
        _ = await sync.enable(workspace: home)
        await store.setFailing(true)

        #expect(await sync.sync(workspace: home) == .failed)
    }

    @Test func tasksThatCannotBeLoadedReportFailedAndTouchNothing() async {
        let sync = CalendarSync(
            store: store, settings: settings, tasks: { _ in throw DocumentsError.unreachable },
            workspaceName: { _ in "Thuis" }, typeTitle: { $0 }, today: { Self.today }
        )
        settings.enable(workspace: home, calendarID: "earlier")

        #expect(await sync.sync(workspace: home) == .failed)
        #expect(await store.calendars.isEmpty)
    }

    @Test func deletedCalendarIsMadeAgainWhileSwitchedOn() async throws {
        tasks.value = [home: [openTask()]]
        let sync = makeSync()
        _ = await sync.enable(workspace: home)
        let first = try calendarID(home)
        await store.userDeletesCalendar(id: first)

        let result = await sync.sync(workspace: home)

        #expect(result == .done(created: 1, updated: 0, deleted: 0))
        let second = try calendarID(home)
        #expect(second != first)
        #expect(await store.calendars == [second: "Brievie – Thuis"])
        #expect(await store.storedEvents(calendarID: second).count == 1)
    }

    @Test func concurrentSyncsCreateOneEvent() async throws {
        let sync = makeSync()
        _ = await sync.enable(workspace: home)
        tasks.value = [home: [openTask()]]

        async let first = sync.sync(workspace: home)
        async let second = sync.sync(workspace: home)
        async let third = sync.sync(workspace: home)
        let results = await [first, second, third]

        #expect(results.contains(.done(created: 1, updated: 0, deleted: 0)))
        #expect(await store.storedEvents(calendarID: try calendarID(home)).count == 1)
        #expect(await store.maxConcurrentApplies == 1)
    }

    @Test func twoWorkspacesUseTwoCalendars() async throws {
        tasks.value = [home: [openTask("Thuisfactuur")], business: [openTask("Zaakfactuur")]]
        let sync = makeSync()

        _ = await sync.enable(workspace: home)
        _ = await sync.enable(workspace: business)

        let homeID = try calendarID(home)
        let businessID = try calendarID(business)
        #expect(homeID != businessID)
        #expect(await store.calendars == [homeID: "Brievie – Thuis", businessID: "Brievie – Zaak"])
        #expect(await store.storedEvents(calendarID: homeID).map(\.title) == ["Betalen: Thuisfactuur"])
        #expect(await store.storedEvents(calendarID: businessID).map(\.title) == ["Betalen: Zaakfactuur"])
    }

    // MARK: - Which calendar is the workspace's

    @Test func twoWorkspacesWithTheSameNameGetTwoCalendarsAndKeepTheirOwnEvents() async throws {
        let homeTask = openTask("Van thuis")
        let otherTask = openTask("Van de andere")
        tasks.value = [home: [homeTask], business: [otherTask]]
        let sync = makeSync(names: [home: "Thuis", business: "Thuis"])

        _ = await sync.enable(workspace: home)
        _ = await sync.enable(workspace: business)
        #expect(await sync.sync(workspace: home) == .done(created: 0, updated: 0, deleted: 0))
        #expect(await sync.sync(workspace: business) == .done(created: 0, updated: 0, deleted: 0))

        let homeID = try calendarID(home)
        let otherID = try calendarID(business)
        #expect(homeID != otherID)
        #expect(await store.calendars == [homeID: "Brievie – Thuis", otherID: "Brievie – Thuis"])
        #expect(await store.storedEvents(calendarID: homeID).map(\.taskID) == [homeTask.id])
        #expect(await store.storedEvents(calendarID: otherID).map(\.taskID) == [otherTask.id])

        await sync.disable(workspace: home, removeCalendar: true)
        #expect(await store.calendars == [otherID: "Brievie – Thuis"])
    }

    @Test func aCalendarWithTheSameTitleHoldingAnEventOfTheUserIsNotAdopted() async throws {
        let usersCalendar = await store.userAddsCalendar(title: "Brievie – Thuis")
        await store.userAddsEvent(title: "Verjaardag", day: Self.today, calendarID: usersCalendar)
        tasks.value = [home: [openTask()]]

        _ = await makeSync().enable(workspace: home)

        let id = try calendarID(home)
        #expect(id != usersCalendar)
        #expect(await store.storedEvents(calendarID: usersCalendar).map(\.title) == ["Verjaardag"])
    }

    @Test func aCalendarWithTheSameTitleInAnotherSourceIsNotAdopted() async throws {
        let local = CalendarSource(id: "local", title: "Op mijn iPhone", kind: .local)
        await store.setSources([FakeCalendarStore.iCloud, local], defaultSourceID: FakeCalendarStore.iCloud.id)
        let elsewhere = await store.userAddsCalendar(title: "Brievie – Thuis", sourceID: local.id)

        _ = await makeSync().enable(workspace: home)

        #expect(try calendarID(home) != elsewhere)
    }

    @Test func anEmptyCalendarWithTheSameTitleInTheDefaultSourceIsAdopted() async throws {
        // Pairing again: the calendar of the earlier pairing is still there.
        let earlier = await store.userAddsCalendar(title: "Brievie – Thuis")

        _ = await makeSync().enable(workspace: home)

        #expect(try calendarID(home) == earlier)
        #expect(await store.calendars.count == 1)
    }

    @Test func withoutTheWorkspacesNameNoCalendarIsMade() async {
        let sync = makeSync(names: [:])

        #expect(await sync.enable(workspace: home) == .failed)
        settings.enable(workspace: home, calendarID: "earlier")
        #expect(await sync.sync(workspace: home) == .failed)
        #expect(await store.calendars.isEmpty)
    }

    @Test func unpairingDuringASyncIsNotUndoneByIt() async throws {
        tasks.value = [home: [openTask()]]
        _ = await makeSync().enable(workspace: home)
        await store.userDeletesCalendar(id: try calendarID(home))
        let settings = settings
        // The settings are cleared while this sync waits for the server.
        let sync = CalendarSync(
            store: store, settings: settings,
            tasks: { _ in
                settings.removeAll()
                return []
            },
            workspaceName: { _ in "Thuis" }, typeTitle: { $0 }, today: { Self.today }
        )

        #expect(await sync.sync(workspace: home) == .off)
        #expect(settings.calendarIDs().isEmpty)
    }

    @Test func disableWithRemoveDeletesOnlyThatCalendar() async throws {
        tasks.value = [home: [openTask()], business: [openTask()]]
        let sync = makeSync()
        let ownCalendar = await store.userAddsCalendar(title: "Werk")
        _ = await sync.enable(workspace: home)
        _ = await sync.enable(workspace: business)
        let businessID = try calendarID(business)

        await sync.disable(workspace: home, removeCalendar: true)

        #expect(!settings.isEnabled(for: home))
        #expect(settings.isEnabled(for: business))
        #expect(await store.calendars == [ownCalendar: "Werk", businessID: "Brievie – Zaak"])
        #expect(await sync.sync(workspace: home) == .off)
    }

    @Test func disableWithoutRemoveKeepsTheCalendarAndEnablingFindsItAgain() async throws {
        tasks.value = [home: [openTask()]]
        let sync = makeSync()
        _ = await sync.enable(workspace: home)
        let id = try calendarID(home)

        await sync.disable(workspace: home, removeCalendar: false)
        #expect(await store.calendars == [id: "Brievie – Thuis"])

        #expect(await sync.enable(workspace: home) == .done(created: 0, updated: 0, deleted: 0))
        #expect(try calendarID(home) == id)
    }

    @Test func eventsTheUserAddedToTheCalendarStay() async throws {
        let sync = makeSync()
        _ = await sync.enable(workspace: home)
        let id = try calendarID(home)
        await store.userAddsEvent(title: "Verjaardag", day: Self.today, calendarID: id)

        #expect(await sync.sync(workspace: home) == .done(created: 0, updated: 0, deleted: 0))
        #expect(await store.storedEvents(calendarID: id).map(\.title) == ["Verjaardag"])
    }
}
