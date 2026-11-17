@testable import BrievieCore
@testable import FeatureWorkspace
import Foundation
import Testing

/// "Ontkoppelen" with calendar switches on: the confirmation also offers to remove the calendars.
@MainActor
@Suite struct WorkspacesUnpairCalendarTests {
    private let server = WorkspaceServer()
    private let secrets = InMemorySecretStore()
    private let connection: ServerConnection
    private let appModel: AppModel
    private let calendars = FakeCalendarStore()
    private let settings = InMemoryCalendarSettings()
    private let sync: CalendarSync
    private let home = UUID()

    init() throws {
        let url = try #require(URL(string: "https://brievie.local"))
        connection = ServerConnection(urls: [url], caCertificateDER: nil, deviceID: UUID(), userName: "Beheerder")
        let store = ConnectionStore(secrets: secrets)
        try store.save(connection, token: "device-token")
        appModel = AppModel(
            store: store, authenticator: NoAuthentication(), launchFlag: InMemoryLaunchFlag(hasLaunchedBefore: true),
            isProtectedDataAvailable: { true }, calendarSettings: settings
        )
        appModel.didPair(connection)
        sync = CalendarSync(
            store: calendars, settings: settings, tasks: { _ in [] }, workspaceName: { _ in "Thuis" },
            typeTitle: { $0 }, today: { CalendarDate(year: 2026, month: 11, day: 17) }
        )
    }

    private func model() -> WorkspacesModel {
        WorkspacesModel(
            connection: connection, store: ConnectionStore(secrets: secrets), server: server, appModel: appModel,
            unpairing: Unpairing(
                server: server, uploads: ScriptedUploadQueue(count: 0), calendarSettings: settings, calendarSync: sync
            )
        )
    }

    @Test func withoutACalendarSwitchOnTheConfirmationOffersOnlyUnpairing() async {
        let model = model()

        model.requestUnpair()
        await model.unpairCountTask?.value

        #expect(model.isConfirmingUnpair)
        #expect(!model.offersCalendarRemoval)
    }

    @Test func removingTheCalendarsTooDeletesThemBeforeForgetting() async throws {
        #expect(await sync.enable(workspace: home) == .done(created: 0, updated: 0, deleted: 0))
        let model = model()
        model.requestUnpair()
        await model.unpairCountTask?.value
        #expect(model.offersCalendarRemoval)

        model.confirmUnpair(removingCalendars: true)
        await appModel.unpairTask?.value

        #expect(appModel.state == .unpaired(notice: nil))
        #expect(await calendars.calendars.isEmpty)
        #expect(settings.calendarIDs().isEmpty)
    }

    @Test func plainUnpairingKeepsTheCalendar() async throws {
        #expect(await sync.enable(workspace: home) == .done(created: 0, updated: 0, deleted: 0))
        let model = model()

        model.confirmUnpair()
        await appModel.unpairTask?.value

        #expect(appModel.state == .unpaired(notice: nil))
        #expect(await calendars.calendars.count == 1)
        #expect(settings.calendarIDs().isEmpty)
    }

    @Test func theSecondChoiceSaysWhatItDoes() {
        #expect(WorkspaceStrings.unpairRemovingCalendars == "Ontkoppelen en agenda's verwijderen")
    }
}
