@testable import BrievieCore
import Foundation
import Testing

/// "Ontkoppelen" and a revocation with calendar switches on: the switches always go, the calendars only when
/// the user chose "Ontkoppelen en agenda's verwijderen".
@MainActor
@Suite struct AppModelUnpairCalendarTests {
    private let secrets = InMemorySecretStore()
    private var store: ConnectionStore { ConnectionStore(secrets: secrets) }
    private let server: FakeBrievieServer
    private let uploads = EmptyUploadQueue()
    private let connection: ServerConnection
    private let calendars = FakeCalendarStore()

    init() throws {
        server = try FakeBrievieServer()
        let url = try #require(URL(string: "https://brievie.local"))
        connection = ServerConnection(urls: [url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn")
        try ConnectionStore(secrets: secrets).save(connection, token: "device-token")
    }

    private func readyModel(calendarSettings: (any CalendarSettings)? = nil) async -> AppModel {
        let model = AppModel(
            store: store, authenticator: FakeAuthenticator(), launchFlag: InMemoryLaunchFlag(hasLaunchedBefore: true),
            isProtectedDataAvailable: { true }, calendarSettings: calendarSettings
        )
        model.start()
        await model.unlock()
        return model
    }

    private func expectNothingStored(sourceLocation: SourceLocation = #_sourceLocation) throws {
        #expect(try store.load() == nil, sourceLocation: sourceLocation)
    }

    /// Two workspaces with their switch on, each with its own calendar.
    private func enableTwoCalendars() async throws -> (InMemoryCalendarSettings, CalendarSync) {
        let settings = InMemoryCalendarSettings()
        let home = UUID()
        let sync = CalendarSync(
            store: calendars, settings: settings, tasks: { _ in [] },
            workspaceName: { $0 == home ? "Thuis" : "Zaak" }, typeTitle: { $0 },
            today: { CalendarDate(year: 2026, month: 11, day: 17) }
        )
        #expect(await sync.enable(workspace: home) == .done(created: 0, updated: 0, deleted: 0))
        #expect(await sync.enable(workspace: UUID()) == .done(created: 0, updated: 0, deleted: 0))
        #expect(await calendars.calendars.count == 2)
        return (settings, sync)
    }

    @Test func unpairingAndRemovingCalendarsDeletesEachWorkspacesCalendar() async throws {
        let (settings, sync) = try await enableTwoCalendars()
        let unpairing = Unpairing(server: server, uploads: uploads, calendarSettings: settings, calendarSync: sync)
        #expect(unpairing.hasCalendars)
        let model = await readyModel()

        let unpaired = await model.unpair(unpairing.removingCalendars())

        #expect(unpaired)
        #expect(await calendars.calendars.isEmpty)
        #expect(settings.calendarIDs().isEmpty)
        #expect(!unpairing.hasCalendars)
        try expectNothingStored()
    }

    @Test func plainUnpairingKeepsTheCalendars() async throws {
        let (settings, sync) = try await enableTwoCalendars()
        let unpairing = Unpairing(server: server, uploads: uploads, calendarSettings: settings, calendarSync: sync)
        let model = await readyModel()

        await model.unpair(unpairing)

        #expect(await calendars.calendars.count == 2)
        #expect(settings.calendarIDs().isEmpty)
        #expect(model.state == .unpaired(notice: nil))
    }

    @Test func aCalendarThatCannotBeRemovedNeverBlocksUnpairing() async throws {
        let (settings, sync) = try await enableTwoCalendars()
        await calendars.setFailing(true)
        let unpairing = Unpairing(server: server, uploads: uploads, calendarSettings: settings, calendarSync: sync)
        let model = await readyModel()

        let unpaired = await model.unpair(unpairing.removingCalendars())

        #expect(unpaired)
        #expect(await calendars.calendars.count == 2)
        #expect(settings.calendarIDs().isEmpty)
        try expectNothingStored()
    }

    @Test func aRevocationTurnsTheCalendarSwitchesOffButKeepsTheCalendars() async throws {
        let (settings, _) = try await enableTwoCalendars()
        let model = await readyModel(calendarSettings: settings)

        model.sessionRevoked(deviceID: connection.deviceID)

        #expect(model.state == .unpaired(notice: AppStrings.sessionRevoked))
        #expect(settings.calendarIDs().isEmpty)
        #expect(await calendars.calendars.count == 2)
    }

    @Test func aSyncThatHoldsTheCalendarNeverHoldsUnpairingPastTheTimeout() async throws {
        let settings = InMemoryCalendarSettings()
        let home = UUID()
        settings.enable(workspace: home, calendarID: "held")
        // The open tasks never come while the test runs: the sync holds the workspace until `release`.
        let (held, release) = AsyncStream<Void>.makeStream()
        let sync = CalendarSync(
            store: calendars, settings: settings,
            tasks: { _ in
                for await _ in held {}
                return []
            },
            workspaceName: { _ in "Thuis" }, typeTitle: { $0 }, today: { CalendarDate(year: 2026, month: 11, day: 17) }
        )
        let running = Task { await sync.sync(workspace: home) }
        let unpairing = Unpairing(
            server: server, uploads: uploads, calendarSettings: settings, calendarSync: sync,
            timeout: .milliseconds(200)
        )
        let model = await readyModel()
        let clock = ContinuousClock()
        let start = clock.now

        let unpaired = await model.unpair(unpairing.removingCalendars())

        #expect(clock.now - start < .seconds(3))
        #expect(unpaired)
        #expect(settings.calendarIDs().isEmpty)
        try expectNothingStored()

        // The removal that waited finishes later and writes nothing back.
        release.finish()
        _ = await running.value
        for _ in 0..<50 { await Task.yield() }
        #expect(settings.calendarIDs().isEmpty)
    }
}
