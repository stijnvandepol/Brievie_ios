@testable import BrievieCore
import BrievieScan
import Foundation
import Testing

/// After the server revoked this device the calendars must go, also when that cannot happen at once: without
/// calendar access, or when the app is ended halfway. What is still to remove is stored apart from the switches
/// and tried again on every activation.
@MainActor
@Suite struct CalendarRevocationCleanupTests {
    private let secrets = InMemorySecretStore()
    private var store: ConnectionStore { ConnectionStore(secrets: secrets) }
    private let connection: ServerConnection
    private let calendars = FakeCalendarStore()
    private let settings = InMemoryCalendarSettings()

    init() throws {
        let url = try #require(URL(string: "https://brievie.local"))
        connection = ServerConnection(urls: [url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn")
        try ConnectionStore(secrets: secrets).save(connection, token: "device-token")
    }

    private func makeSync() -> CalendarSync {
        CalendarSync(
            store: calendars, settings: settings, tasks: { _ in [] }, workspaceName: { _ in "Thuis" },
            typeTitle: { $0 }, today: { CalendarDate(year: 2026, month: 11, day: 17) }
        )
    }

    private func makeModel(_ sync: CalendarSync) -> AppModel {
        AppModel(
            store: store, authenticator: FakeAuthenticator(), launchFlag: InMemoryLaunchFlag(hasLaunchedBefore: true),
            isProtectedDataAvailable: { true }, calendarSettings: settings, calendarSync: sync
        )
    }

    private func readyModel(_ sync: CalendarSync) async -> AppModel {
        let model = makeModel(sync)
        model.start()
        await model.unlock()
        return model
    }

    @Test func withoutCalendarAccessRemovingACalendarFailsInsteadOfReportingItGone() async throws {
        let sync = makeSync()
        _ = await sync.enable(workspace: UUID())
        let id = try #require(settings.calendarIDs().values.first)
        await calendars.setAccess(.denied, grantsOnRequest: false)

        await #expect(throws: CalendarStoreError.self) {
            try await calendars.removeCalendar(id: id)
        }
        #expect(await calendars.calendars[id] != nil)
    }

    @Test func aRemovalWithoutAccessStaysPendingAndIsDoneOnALaterActivation() async throws {
        let sync = makeSync()
        _ = await sync.enable(workspace: UUID())
        let id = try #require(settings.calendarIDs().values.first)
        let model = await readyModel(sync)
        await calendars.setAccess(.denied, grantsOnRequest: false)

        model.sessionRevoked(deviceID: connection.deviceID)
        await model.calendarRemovalTask?.value

        #expect(settings.calendarIDs().isEmpty)
        #expect(await calendars.calendars[id] != nil)
        #expect(settings.pendingRemovals().keys.contains(id))

        await calendars.setAccess(.granted, grantsOnRequest: true)
        await model.didBecomeActive()
        await model.calendarRemovalTask?.value

        #expect(await calendars.calendars.isEmpty)
        #expect(settings.pendingRemovals().isEmpty)
    }

    @Test func theCalendarsToRemoveAreStoredBeforeTheSwitchesAreCleared() async throws {
        let sync = makeSync()
        _ = await sync.enable(workspace: UUID())
        let id = try #require(settings.calendarIDs().values.first)
        let model = await readyModel(sync)
        await calendars.setFailing(true)

        model.sessionRevoked(deviceID: connection.deviceID)
        await model.calendarRemovalTask?.value

        // The app is ended here; a new process finds what is left and finishes it on its first activation.
        await calendars.setFailing(false)
        let next = makeModel(sync)
        next.start()
        await next.didBecomeActive()
        await next.calendarRemovalTask?.value

        #expect(await calendars.calendars[id] == nil)
        #expect(settings.pendingRemovals().isEmpty)
    }

    @Test func clearingTheSwitchesLeavesThePendingRemovals() {
        settings.markForRemoval(["calendar-1": UUID()])

        settings.removeAll()

        #expect(settings.pendingRemovals().keys.contains("calendar-1"))
        settings.removalDone(calendarID: "calendar-1")
        #expect(settings.pendingRemovals().isEmpty)
    }

    @Test func theUserDefaultsSettingsKeepPendingRemovalsApartFromTheSwitches() {
        let settings = UserDefaultsCalendarSettings(suiteName: "calendar-pending-\(UUID().uuidString)")
        let workspace = UUID()
        settings.enable(workspace: workspace, calendarID: "a", sourceID: "icloud")

        settings.markForRemoval(["a": workspace])
        settings.removeAll()

        #expect(settings.calendarIDs().isEmpty)
        #expect(settings.pendingRemovals() == ["a": workspace])
        settings.removalDone(calendarID: "a")
        #expect(settings.pendingRemovals().isEmpty)
    }

    @Test func aCalendarANewPairingTookOverIsNotRemoved() async throws {
        let sync = makeSync()
        let workspace = UUID()
        _ = await sync.enable(workspace: workspace)
        let id = try #require(settings.calendarID(for: workspace))
        settings.markForRemoval([id: workspace])

        await sync.removePendingRemovals()

        #expect(await calendars.calendars[id] != nil)
        #expect(settings.pendingRemovals().isEmpty)
    }

    @Test func aCalendarPendingRemovalIsNeverAdoptedByANewPairing() async throws {
        // Revoked without access: the old workspace's calendar waits for removal. After pairing again (a new
        // workspace id, the same name) switching on must make a new calendar: the removal may run at any moment
        // and would delete one it adopted.
        let sync = makeSync()
        let old = UUID()
        _ = await sync.enable(workspace: old)
        let pending = try #require(settings.calendarID(for: old))
        settings.markForRemoval([pending: old])
        settings.removeAll()

        let new = UUID()
        _ = await sync.enable(workspace: new)
        let adopted = try #require(settings.calendarID(for: new))
        #expect(adopted != pending)

        await sync.removePendingRemovals()
        #expect(await calendars.calendars[adopted] != nil)
        #expect(await calendars.calendars[pending] == nil)
    }

    @Test func aCalendarPendingRemovalIsNotTakenAgainWhenASyncRemakesOne() async throws {
        let sync = makeSync()
        let old = UUID()
        _ = await sync.enable(workspace: old)
        let pending = try #require(settings.calendarID(for: old))
        settings.markForRemoval([pending: old])
        settings.removeAll()
        // A switch whose calendar was deleted: the sync makes it again and must not pick the pending one.
        let new = UUID()
        settings.enable(workspace: new, calendarID: "deleted", sourceID: FakeCalendarStore.iCloud.id)

        _ = await sync.sync(workspace: new)

        #expect(settings.calendarID(for: new) != pending)
    }

    @Test func aRevocationWhileAnUnpairThatKeptTheCalendarsIsPendingKeepsThem() async throws {
        let sync = makeSync()
        _ = await sync.enable(workspace: UUID())
        let model = await readyModel(sync)
        let unpairing = Unpairing(
            server: try FakeBrievieServer(), uploads: StuckUploadQueue(), calendarSettings: settings,
            calendarSync: sync, timeout: .milliseconds(10)
        )

        // "Ontkoppelen" (keep the calendars): the queue cannot be emptied, so the forget stays pending.
        #expect(await model.unpair(unpairing) == false)
        model.sessionRevoked(deviceID: connection.deviceID)
        await model.calendarRemovalTask?.value

        #expect(await calendars.calendars.count == 1)
        #expect(settings.pendingRemovals().isEmpty)
    }
}

/// An upload queue that can never be emptied.
private struct StuckUploadQueue: UploadQueue {
    struct Stuck: Error {}

    func enqueue(pages: [ScannedPage], workspaceID: UUID) async throws(UploadQueueError) -> UploadItem {
        throw UploadQueueError.writeFailed
    }

    func items() async -> [UploadItem] { [] }
    func retry(_ id: UUID) async {}
    func delete(_ id: UUID) async {}
    func removeAll() async throws { throw Stuck() }
    func progressUpdates() async -> AsyncStream<[UUID: Double]> { AsyncStream { $0.finish() } }
    func takeRemovedUnreadableCount() async -> Int { 0 }
}
