import BrievieCore
import BrievieUI
import FeatureDocuments
import FeaturePairing
import FeatureWorkspace
import SwiftUI

/// Switches on `AppModel.state`; hides everything but the app name while the app is not in the foreground.
struct RootView: View {
    let appModel: AppModel
    let environment: AppEnvironment

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .tint(BrievieColor.brand)
            .overlay {
                if hidesContent {
                    PrivacyCover()
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .background:
                    appModel.didEnterBackground()
                case .active:
                    appModel.sceneActivated()
                default:
                    break
                }
            }
            // Queued scans go out as soon as there is a usable pairing (at launch, after pairing again).
            .onChange(of: isReady, initial: true) { _, ready in
                if ready {
                    Task { await environment.uploads.resume() }
                }
            }
            // The first-launch check waits for protected data; run it as soon as the device is unlocked.
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.protectedDataDidBecomeAvailableNotification
            )) { _ in
                appModel.protectedDataDidBecomeAvailable()
            }
    }

    @ViewBuilder private var content: some View {
        switch appModel.state {
        case .unpaired(let notice):
            PairingScreen(appModel: appModel, environment: environment, notice: notice)
        case .locked:
            LockView(unlock: { appModel.requestUnlock() })
        case .ready(let connection):
            WorkspacesScreen(appModel: appModel, environment: environment, connection: connection)
        }
    }

    private var isReady: Bool {
        if case .ready = appModel.state { return true }
        return false
    }

    /// The app switcher takes its snapshot when the scene leaves the foreground: nothing from a paired app
    /// may be on screen by then. Pairing shows no personal data.
    private var hidesContent: Bool {
        if case .unpaired = appModel.state { return false }
        return scenePhase != .active
    }
}

private struct PairingScreen: View {
    @State private var model: PairingModel
    private let notice: String?

    init(appModel: AppModel, environment: AppEnvironment, notice: String?) {
        _model = State(initialValue: PairingModel(
            service: PairingService(server: environment.server, store: environment.store),
            camera: LiveCameraAccess(),
            deviceName: { UIDevice.current.name },
            openSettings: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            },
            onPaired: { appModel.didPair($0) }
        ))
        self.notice = notice
    }

    var body: some View {
        PairingView(model: model, notice: notice)
    }
}

private struct WorkspacesScreen: View {
    @State private var model: WorkspacesModel
    private let appModel: AppModel
    private let environment: AppEnvironment
    private let connection: ServerConnection

    init(appModel: AppModel, environment: AppEnvironment, connection: ServerConnection) {
        _model = State(initialValue: WorkspacesModel(
            connection: connection,
            store: environment.store,
            server: environment.server,
            appModel: appModel
        ))
        self.appModel = appModel
        self.environment = environment
        self.connection = connection
    }

    var body: some View {
        WorkspacesView(model: model, showsNoPasscodeWarning: appModel.showsNoPasscodeWarning) { workspace in
            DocumentsScreen(
                appModel: appModel, environment: environment, connection: connection, workspace: workspace
            )
        }
    }
}

/// The post of one workspace. Owns its models for as long as the screen is on the navigation stack.
private struct DocumentsScreen: View {
    @State private var model: DocumentsModel
    @State private var scanModel: ScanFlowModel
    private let title: String

    init(
        appModel: AppModel, environment: AppEnvironment, connection: ServerConnection,
        workspace: WorkspacesModel.Row
    ) {
        let documents = WorkspaceDocuments(
            workspaceID: workspace.id, connection: connection, store: environment.store,
            server: environment.documents
        )
        _model = State(initialValue: DocumentsModel(
            documents: documents,
            uploads: environment.uploads,
            // A role this app does not know may only look.
            canScan: workspace.role == .admin || workspace.role == .member,
            onRevoked: { appModel.sessionRevoked(deviceID: connection.deviceID) },
            onMissingPairing: { appModel.connectionMissing() }
        ))
        _scanModel = State(initialValue: ScanFlowModel(workspaceID: workspace.id, uploads: environment.uploads))
        title = workspace.name
    }

    var body: some View {
        DocumentsView(model: model, scanModel: scanModel, title: title) { _ in
            // The review screen arrives with the next step of this phase.
            EmptyView()
        }
    }
}
