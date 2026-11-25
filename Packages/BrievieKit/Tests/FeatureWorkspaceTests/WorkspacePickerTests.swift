@testable import BrievieCore
@testable import FeatureWorkspace
import Foundation
import Testing

/// The workspace pill and its picker: a button only with another workspace to go to, the current one only closes.
@MainActor
@Suite struct WorkspacePickerTests {
    private let server = WorkspaceServer()
    private let secrets = InMemorySecretStore()
    private let current = InMemoryCurrentWorkspaceStore()
    private let connection: ServerConnection
    private let appModel: AppModel
    private let home = WorkspaceSummary(id: UUID(), name: "Thuis", kind: .home, role: .admin)
    private let business = WorkspaceSummary(id: UUID(), name: "Bedrijf", kind: .business, role: .member)

    init() throws {
        let url = try #require(URL(string: "https://brievie.local"))
        connection = ServerConnection(urls: [url], caCertificateDER: nil, deviceID: UUID(), userName: "Jij")
        let store = ConnectionStore(secrets: secrets)
        try store.save(connection, token: "device-token")
        appModel = AppModel(
            store: store, authenticator: NoAuthentication(), launchFlag: InMemoryLaunchFlag(hasLaunchedBefore: true),
            isProtectedDataAvailable: { true }
        )
        appModel.didPair(connection)
    }

    private func loaded(_ workspaces: [WorkspaceSummary]) async -> WorkspacesModel {
        server.answer = { _ in workspaces }
        let model = WorkspacesModel(
            connection: connection, store: ConnectionStore(secrets: secrets), server: server, appModel: appModel,
            unpairing: Unpairing(server: server, uploads: ScriptedUploadQueue(count: 0)), currentWorkspace: current
        )
        await model.load()
        return model
    }

    @Test func withOneWorkspaceThePillIsNoButton() async {
        let model = await loaded([home])

        model.showPicker()

        #expect(!model.canSwitch)
        #expect(!model.isShowingPicker)
        #expect(model.currentRow?.id == home.id)
        #expect(model.pillAccessibilityLabel(for: WorkspacesModel.Row(workspace: home)) == "Werkruimte: Thuis")
    }

    @Test func withTwoThePillOpensThePicker() async {
        let model = await loaded([home, business])

        model.showPicker()

        #expect(model.canSwitch && model.isShowingPicker)
        #expect(
            model.pillAccessibilityLabel(for: WorkspacesModel.Row(workspace: home))
                == "Werkruimte: Thuis. Kies een andere werkruimte"
        )
    }

    @Test func choosingTheCurrentWorkspaceOnlyCloses() async {
        let model = await loaded([home, business])
        model.showPicker()
        model.isShowingSettings = true

        model.choose(home.id)

        #expect(!model.isShowingPicker)
        #expect(model.currentWorkspaceID == home.id)
        // Nothing else moves: the settings that were open stay open.
        #expect(model.isShowingSettings)
    }

    @Test func choosingAnotherShowsAndRemembersIt() async {
        let model = await loaded([home, business])
        model.showPicker()
        model.isShowingSettings = true

        model.choose(business.id)

        #expect(!model.isShowingPicker && !model.isShowingSettings)
        #expect(model.currentRow?.id == business.id)
        #expect(current.workspace(forDevice: connection.deviceID) == business.id)
    }

    @Test func aTappedReminderClosesThePicker() async {
        let model = await loaded([home, business])
        model.showPicker()

        model.show(ReminderTarget(workspaceID: business.id, documentID: nil))

        #expect(!model.isShowingPicker)
        #expect(model.currentWorkspaceID == business.id)
    }
}
