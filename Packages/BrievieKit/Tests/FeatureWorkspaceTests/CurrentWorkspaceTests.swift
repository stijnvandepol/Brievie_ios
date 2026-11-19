@testable import BrievieCore
@testable import FeatureWorkspace
import Foundation
import Testing

/// Which workspace the inbox shows: the one opened last on this phone, else the first the server lists.
@MainActor
@Suite struct CurrentWorkspaceTests {
    private let server = WorkspaceServer()
    private let secrets = InMemorySecretStore()
    private let current = InMemoryCurrentWorkspaceStore()
    private let connection: ServerConnection
    private let appModel: AppModel
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
    }

    private func makeModel() -> WorkspacesModel {
        WorkspacesModel(
            connection: connection, store: ConnectionStore(secrets: secrets), server: server, appModel: appModel,
            unpairing: Unpairing(server: server, uploads: ScriptedUploadQueue(count: 0)), currentWorkspace: current
        )
    }

    private func serve(_ workspaces: [WorkspaceSummary]) {
        server.answer = { _ in workspaces }
    }

    // MARK: - which one

    @Test func withNothingRememberedTheFirstOfTheServersListIsShownAndRemembered() async {
        serve([business, home])
        let model = makeModel()

        await model.load()

        #expect(model.currentWorkspaceID == business.id)
        #expect(model.root == .inbox(WorkspacesModel.Row(workspace: business)))
        #expect(current.workspace(forDevice: connection.deviceID) == business.id)
    }

    @Test func theRememberedWorkspaceIsShown() async {
        current.remember(home.id, forDevice: connection.deviceID)
        serve([business, home])
        let model = makeModel()

        await model.load()

        #expect(model.currentWorkspaceID == home.id)
        #expect(model.root == .inbox(WorkspacesModel.Row(workspace: home)))
    }

    @Test func aRememberedWorkspaceThatIsNoLongerListedFallsBackToTheFirst() async {
        current.remember(UUID(), forDevice: connection.deviceID)
        serve([home, business])
        let model = makeModel()

        await model.load()

        #expect(model.currentWorkspaceID == home.id)
        #expect(current.workspace(forDevice: connection.deviceID) == home.id)
    }

    @Test func aWorkspaceRemovedOnTheServerMakesWayForTheFirstOnTheNextLoad() async {
        serve([home, business])
        let model = makeModel()
        await model.load()
        model.select(business.id)

        serve([home])
        await model.load()

        #expect(model.currentWorkspaceID == home.id)
        #expect(current.workspace(forDevice: connection.deviceID) == home.id)
    }

    @Test func theChoiceOfAnotherPairingIsNotUsed() async {
        current.remember(home.id, forDevice: UUID())
        serve([business, home])
        let model = makeModel()

        await model.load()

        #expect(model.currentWorkspaceID == business.id)
    }

    // MARK: - switching

    @Test func switchingShowsAndRemembersTheOtherWorkspace() async {
        serve([home, business])
        let model = makeModel()
        await model.load()

        model.select(business.id)

        #expect(model.currentWorkspaceID == business.id)
        #expect(model.root == .inbox(WorkspacesModel.Row(workspace: business)))
        #expect(current.workspace(forDevice: connection.deviceID) == business.id)
    }

    @Test func theSwitchSurvivesAReload() async {
        serve([home, business])
        let model = makeModel()
        await model.load()
        model.select(business.id)

        await model.load()

        #expect(model.currentWorkspaceID == business.id)
    }

    @Test func aWorkspaceThatIsNotListedCannotBeChosen() async {
        serve([home])
        let model = makeModel()
        await model.load()

        model.select(UUID())

        #expect(model.currentWorkspaceID == home.id)
        #expect(current.workspace(forDevice: connection.deviceID) == home.id)
    }

    @Test func aFailedRefreshKeepsTheInbox() async {
        serve([home, business])
        let model = makeModel()
        await model.load()
        model.select(business.id)

        server.answer = { _ in throw ServerError.unreachable }
        await model.load()

        #expect(model.root == .inbox(WorkspacesModel.Row(workspace: business)))
    }

    @Test func unpairingForgetsTheCurrentWorkspace() async {
        let appModel = AppModel(
            store: ConnectionStore(secrets: secrets), authenticator: NoAuthentication(),
            launchFlag: InMemoryLaunchFlag(hasLaunchedBefore: true), isProtectedDataAvailable: { true },
            currentWorkspace: current
        )
        appModel.didPair(connection)
        let model = WorkspacesModel(
            connection: connection, store: ConnectionStore(secrets: secrets), server: server, appModel: appModel,
            unpairing: Unpairing(server: server, uploads: ScriptedUploadQueue(count: 0)), currentWorkspace: current
        )
        serve([home])
        await model.load()
        #expect(current.workspace(forDevice: connection.deviceID) == home.id)

        model.confirmUnpair()
        await appModel.unpairTask?.value

        #expect(appModel.state == .unpaired(notice: nil))
        #expect(current.workspace(forDevice: connection.deviceID) == nil)
    }

    // MARK: - the root screen

    @Test func whileLoadingTheRootSaysSo() {
        #expect(makeModel().root == .loading)
    }

    @Test func aFailedFirstLoadIsTheRootsErrorWithRetry() async {
        server.answer = { _ in throw ServerError.unreachable }
        let model = makeModel()

        await model.load()

        #expect(model.root == .failed(message: WorkspaceStrings.unreachable))
        #expect(model.currentWorkspaceID == nil)
    }

    @Test func noWorkspacesIsTheEmptyRoot() async {
        serve([])
        let model = makeModel()

        await model.load()

        #expect(model.root == .empty)
        #expect(model.currentWorkspaceID == nil)
        #expect(current.workspace(forDevice: connection.deviceID) == nil)
    }

    /// The settings button sits outside the root's states (`WorkspaceRootView`); what it leads to must work in
    /// each of them, "Ontkoppelen" above all, so nobody is stuck on a server that does not answer.
    @Test(arguments: ["loading", "failed", "empty"])
    func unpairingWorksWithoutAnInbox(root: String) async {
        let model = makeModel()
        switch root {
        case "failed":
            server.answer = { _ in throw ServerError.unreachable }
            await model.load()
        case "empty":
            serve([])
            await model.load()
        default:
            break
        }
        #expect(model.currentWorkspaceID == nil)

        model.requestUnpair()
        await model.unpairCountTask?.value
        #expect(model.isConfirmingUnpair)
        model.confirmUnpair()
        await appModel.unpairTask?.value

        #expect(appModel.state == .unpaired(notice: nil))
    }

    // MARK: - naming the workspace

    @Test func withOneWorkspaceTheInboxDoesNotNameIt() async {
        serve([home])
        let model = makeModel()

        await model.load()

        #expect(!model.showsWorkspaceName)
    }

    @Test func withMoreWorkspacesTheInboxNamesIt() async {
        serve([home, business])
        let model = makeModel()

        await model.load()

        #expect(model.showsWorkspaceName)
    }
}
