@testable import BrievieCore
@testable import FeatureWorkspace
import Foundation
import Testing

/// Every workspaces load refreshes the reminders with the workspaces this phone has now; a tapped reminder shows
/// its workspace.
@MainActor
@Suite struct WorkspacesRemindersTests {
    private let server = WorkspaceServer()
    private let secrets = InMemorySecretStore()
    private let connection: ServerConnection
    private let appModel: AppModel
    private let center = InMemoryReminderCenter()
    private let settings = InMemoryReminderSettings()
    private let home = WorkspaceSummary(id: UUID(), name: "Thuis", kind: .home, role: .admin)
    private let business = WorkspaceSummary(id: UUID(), name: "Zaak", kind: .business, role: .member)

    init() throws {
        let url = try #require(URL(string: "https://brievie.local"))
        connection = ServerConnection(urls: [url], caCertificateDER: nil, deviceID: UUID(), userName: "Beheerder")
        let store = ConnectionStore(secrets: secrets)
        try store.save(connection, token: "device-token")
        appModel = AppModel(
            store: store, authenticator: NoAuthentication(), launchFlag: InMemoryLaunchFlag(hasLaunchedBefore: true),
            isProtectedDataAvailable: { true }
        )
        appModel.didPair(connection)
        settings.setEnabled(true)
    }

    private func makeModel() -> WorkspacesModel {
        let reminders = DeadlineReminders(
            center: center, settings: settings,
            tasks: { _ in
                [WorkspaceTask(
                    id: UUID(), type: "pay", description: "", deadline: CalendarDate(year: 2026, month: 12, day: 10),
                    isDone: false, documentID: nil, sender: ""
                )]
            },
            now: { Date(timeIntervalSince1970: 1_795_086_000) },
            timeZone: { TimeZone(identifier: "Europe/Amsterdam") ?? .gmt }
        )
        return WorkspacesModel(
            connection: connection, store: ConnectionStore(secrets: secrets), server: server, appModel: appModel,
            unpairing: Unpairing(server: server, uploads: ScriptedUploadQueue(count: 0)),
            reminders: WorkspaceReminders(reminders: reminders, openSettings: {})
        )
    }

    @Test func aLoadSchedulesForEveryWorkspaceAndDropsOneThatIsGone() async {
        server.answer = { _ in [self.home, self.business] }
        let model = makeModel()

        await model.load()
        await model.reminderTask?.value
        #expect(Set(center.pending.values.map(\.workspaceID)) == [home.id, business.id])

        server.answer = { _ in [self.home] }
        await model.load()
        await model.reminderTask?.value
        #expect(Set(center.pending.values.map(\.workspaceID)) == [home.id])
        #expect(model.reminderModel?.isOn == true)
    }

    @Test func aTappedReminderShowsItsWorkspaceAndClosesTheSettings() async {
        server.answer = { _ in [self.home, self.business] }
        let model = makeModel()
        await model.load()
        model.isShowingSettings = true

        let shown = model.show(ReminderTarget(workspaceID: business.id, documentID: UUID()))

        #expect(shown)
        #expect(model.currentWorkspaceID == business.id)
        #expect(!model.isShowingSettings)
    }

    @Test func aReminderOfAWorkspaceThatIsGoneChangesNothing() async {
        server.answer = { _ in [self.home] }
        let model = makeModel()
        await model.load()

        #expect(!model.show(ReminderTarget(workspaceID: UUID(), documentID: nil)))
        #expect(model.currentWorkspaceID == home.id)
    }
}
