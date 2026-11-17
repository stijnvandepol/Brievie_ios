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

    @Test(.timeLimit(.minutes(1)))
    func aSyncThatHoldsTheCalendarNeverHoldsUnpairingPastTheTimeout() async throws {
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

    @Test(.timeLimit(.minutes(1)))
    func aRemovalThatWaitedNeverRemovesTheCalendarOfANewPairing() async throws {
        let settings = WatchedCalendarSettings()
        let home = UUID()
        let oldCalendar = await calendars.userAddsCalendar(title: "Brievie – Thuis")
        settings.enable(workspace: home, calendarID: oldCalendar)
        let (held, release) = AsyncStream<Void>.makeStream()
        let syncHolds = Locked(false)
        let sync = CalendarSync(
            store: calendars, settings: settings,
            tasks: { _ in
                syncHolds.value = true
                for await _ in held {}
                return []
            },
            workspaceName: { _ in "Thuis" }, typeTitle: { $0 }, today: { CalendarDate(year: 2026, month: 11, day: 17) }
        )
        let running = Task { await sync.sync(workspace: home) }
        // The sync holds the workspace before the removal asks for it.
        while !syncHolds.value { await Task.yield() }
        let unpairing = Unpairing(
            server: server, uploads: uploads, calendarSettings: settings, calendarSync: sync,
            timeout: .milliseconds(200)
        )
        let model = await readyModel()
        #expect(await model.unpair(unpairing.removingCalendars()))

        // Paired again, and the same workspace's switch is on with a new calendar before the old removal ran.
        let newCalendar = await calendars.userAddsCalendar(title: "Brievie – Thuis")
        settings.enable(workspace: home, calendarID: newCalendar)
        settings.startWatching()
        release.finish()
        _ = await running.value
        // Wait for the waiting removal's own turn: it either checks the clear generation (with the check: the
        // released sync reads it once, the removal once) or, without the check, turns the switch off.
        while settings.generationReads < 2, settings.disables == 0 { await Task.yield() }

        #expect(settings.disables == 0)
        #expect(settings.calendarID(for: home) == newCalendar)
        #expect(await calendars.calendars[newCalendar] != nil)
    }
}

/// In-memory calendar settings that count, from `startWatching()` on, the reads of the clear generation and the
/// switches turned off: a test can wait for a late `disable` to take its turn without timing.
private final class WatchedCalendarSettings: CalendarSettings {
    private let inner = InMemoryCalendarSettings()
    private let counts = Locked((watching: false, generationReads: 0, disables: 0))

    var generationReads: Int { counts.value.generationReads }
    var disables: Int { counts.value.disables }

    func startWatching() {
        counts.update { $0.watching = true }
    }

    func calendarID(for workspace: UUID) -> String? { inner.calendarID(for: workspace) }
    func calendarIDs() -> [UUID: String] { inner.calendarIDs() }
    func isEnabled(for workspace: UUID) -> Bool { inner.isEnabled(for: workspace) }
    func enable(workspace: UUID, calendarID: String) { inner.enable(workspace: workspace, calendarID: calendarID) }
    func removeAll() { inner.removeAll() }

    func disable(workspace: UUID) {
        counts.update { if $0.watching { $0.disables += 1 } }
        inner.disable(workspace: workspace)
    }

    func clearGeneration() -> Int {
        counts.update { if $0.watching { $0.generationReads += 1 } }
        return inner.clearGeneration()
    }

    func enable(workspace: UUID, calendarID: String, ifGeneration generation: Int) -> Bool {
        inner.enable(workspace: workspace, calendarID: calendarID, ifGeneration: generation)
    }
}
