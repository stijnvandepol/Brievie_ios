@testable import BrievieCore
@testable import FeatureWorkspace
import Foundation
import Synchronization
import Testing

/// The "Zet deadlines in mijn agenda" switch of one workspace.
@MainActor
@Suite struct CalendarSettingModelTests {
    private let store = FakeCalendarStore()
    private let settings = InMemoryCalendarSettings()
    private let workspace = UUID()
    private let openedSettings = Locked(0)

    private func makeModel() -> CalendarSettingModel {
        let task = WorkspaceTask(
            id: UUID(), type: "pay", description: "Factuur", deadline: CalendarDate(year: 2026, month: 12, day: 1),
            isDone: false, documentID: nil, sender: "Eneco"
        )
        let sync = CalendarSync(
            store: store, settings: settings, tasks: { _ in [task] }, workspaceName: { _ in "Thuis" },
            typeTitle: { $0 }, today: { CalendarDate(year: 2026, month: 11, day: 16) }
        )
        let openedSettings = openedSettings
        return CalendarSettingModel(
            workspaceID: workspace, workspaceName: "Thuis", sync: sync, settings: settings,
            openSettings: { openedSettings.value += 1 }
        )
    }

    private func calendarID() throws -> String {
        try #require(settings.calendarID(for: workspace))
    }

    @Test func startsOffAndFollowsTheStoredSetting() {
        #expect(!makeModel().isOn)

        settings.enable(workspace: workspace, calendarID: "calendar-1")

        #expect(makeModel().isOn)
    }

    @Test func switchingOnMakesTheCalendarAndFillsIt() async throws {
        let model = makeModel()

        model.toggle(true)
        #expect(model.isOn)
        await model.pendingTask?.value

        #expect(model.isOn)
        #expect(model.message == nil)
        #expect(await store.storedEvents(calendarID: try calendarID()).count == 1)
    }

    @Test func refusedAccessTurnsTheSwitchOffWithAMessage() async {
        await store.setAccess(.notDetermined, grantsOnRequest: false)
        let model = makeModel()

        model.toggle(true)
        await model.pendingTask?.value

        #expect(!model.isOn)
        #expect(model.message == "Brievie mag niet bij je agenda. Zet het aan in Instellingen.")
        #expect(model.showsOpenSettings)
        #expect(!settings.isEnabled(for: workspace))
        #expect(await store.calendars.isEmpty)

        model.openSettings()
        #expect(openedSettings.value == 1)
    }

    @Test func aCalendarThatCannotBeMadeTurnsTheSwitchOffWithAnError() async {
        await store.setFailing(true)
        let model = makeModel()

        model.toggle(true)
        await model.pendingTask?.value

        #expect(!model.isOn)
        #expect(model.message == WorkspaceStrings.generic)
        #expect(!model.showsOpenSettings)
    }

    @Test func switchingOffAsksWhetherToRemoveTheCalendar() async {
        settings.enable(workspace: workspace, calendarID: "calendar-1")
        let model = makeModel()

        model.toggle(false)

        #expect(model.isAskingToRemove)
        #expect(model.isOn, "The switch stays on until the user answered")
        #expect(model.removeQuestion == "Agenda 'Brievie – Thuis' ook verwijderen?")
    }

    @Test func removeDeletesTheCalendarAndTurnsTheSwitchOff() async throws {
        let model = makeModel()
        model.toggle(true)
        await model.pendingTask?.value
        model.toggle(false)

        model.switchOff(removeCalendar: true)
        await model.pendingTask?.value

        #expect(!model.isOn)
        #expect(!model.isAskingToRemove)
        #expect(!settings.isEnabled(for: workspace))
        #expect(await store.calendars.isEmpty)
    }

    @Test func keepLeavesTheCalendarAndTurnsTheSwitchOff() async throws {
        let model = makeModel()
        model.toggle(true)
        await model.pendingTask?.value
        let id = try calendarID()
        model.toggle(false)

        model.switchOff(removeCalendar: false)
        await model.pendingTask?.value

        #expect(!model.isOn)
        #expect(!settings.isEnabled(for: workspace))
        #expect(await store.calendars == [id: "Brievie – Thuis"])
    }

    @Test func catalogAndCodeAgreeOnTheFormats() throws {
        #expect(
            try CatalogParity.dutchValue(forKey: "workspaces.calendar.remove.question", target: "FeatureWorkspace")
                == WorkspaceStrings.calendarRemoveQuestionFormat
        )
    }
}

/// The calendar switches on the Workspaces screen.
@MainActor
@Suite struct WorkspacesCalendarTests {
    private let server = WorkspaceServer()
    private let store = ConnectionStore(secrets: InMemorySecretStore())
    private let connection: ServerConnection
    private let appModel: AppModel

    init() throws {
        let url = try #require(URL(string: "https://brievie.local"))
        connection = ServerConnection(urls: [url], caCertificateDER: nil, deviceID: UUID(), userName: "Beheerder")
        try store.save(connection, token: "device-token")
        appModel = AppModel(
            store: store,
            authenticator: NoAuthentication(),
            launchFlag: InMemoryLaunchFlag(hasLaunchedBefore: true),
            isProtectedDataAvailable: { true }
        )
        appModel.didPair(connection)
    }

    private func summary(_ name: String, kind: WorkspaceSummary.Kind = .home) -> WorkspaceSummary {
        WorkspaceSummary(id: UUID(), name: name, kind: kind, role: .admin)
    }

    @Test func loadedWorkspacesGetACalendarSwitchAndAreReported() async {
        let thuis = summary("Thuis")
        let zaak = summary("Zaak", kind: .business)
        server.answer = { _ in [thuis, zaak] }
        let reported = Locked<[String]>([])
        let settings = InMemoryCalendarSettings()
        settings.enable(workspace: zaak.id, calendarID: "calendar-1")
        let model = WorkspacesModel(
            connection: connection, store: store, server: server, appModel: appModel,
            unpairing: Unpairing(server: server, uploads: ScriptedUploadQueue(count: 0)),
            calendar: WorkspaceCalendar(
                sync: CalendarSync(
                    store: FakeCalendarStore(), settings: settings, tasks: { _ in [] }, workspaceName: { _ in "" },
                    typeTitle: { $0 }, today: { CalendarDate(year: 2026, month: 11, day: 16) }
                ),
                settings: settings,
                openSettings: {},
                didLoad: { rows in reported.value = rows.map(\.name) }
            )
        )

        await model.load()

        #expect(reported.value == ["Thuis", "Zaak"])
        #expect(model.calendarModel(for: thuis.id)?.isOn == false)
        #expect(model.calendarModel(for: zaak.id)?.isOn == true)
        #expect(model.calendarModel(for: zaak.id)?.workspaceName == "Zaak")
        let first = model.calendarModel(for: thuis.id)
        await model.load()
        #expect(model.calendarModel(for: thuis.id) === first, "A reload keeps the switch's model")
    }

    @Test func withoutCalendarSupportThereIsNoSwitch() async {
        let thuis = summary("Thuis")
        server.answer = { _ in [thuis] }

        let model = WorkspacesModel(
            connection: connection, store: store, server: server, appModel: appModel,
            unpairing: Unpairing(server: server, uploads: ScriptedUploadQueue(count: 0))
        )

        await model.load()

        #expect(model.calendarModel(for: thuis.id) == nil)
    }
}

/// A value behind a lock, for `@Sendable` closures in tests.
final class Locked<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>

    init(_ value: Value) {
        mutex = Mutex(value)
    }

    var value: Value {
        get { mutex.withLock { $0 } }
        set { mutex.withLock { $0 = newValue } }
    }
}
