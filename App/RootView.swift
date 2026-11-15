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
    /// The pairing whose screens are in the view tree (also while locked); `nil` until the first unlock.
    @State private var shownConnection: ServerConnection?

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

    /// The paired app stays in the view tree while it is locked, under an opaque lock screen: a review that
    /// is half filled in must survive a trip to another app. (Its sheets close themselves when the scene
    /// leaves the foreground, so nothing of it shows above the lock.)
    @ViewBuilder private var content: some View {
        if case .unpaired(let notice) = appModel.state {
            PairingScreen(appModel: appModel, environment: environment, notice: notice)
        } else {
            ZStack {
                if let connection = shownConnection {
                    WorkspacesScreen(appModel: appModel, environment: environment, connection: connection)
                        // A new pairing is a new app: nothing of the old one is kept.
                        .id(connection.deviceID)
                        .accessibilityHidden(isLocked)
                        .allowsHitTesting(!isLocked)
                }
                if isLocked {
                    LockView(unlock: { appModel.requestUnlock() })
                        .background(Color(.systemGroupedBackground).ignoresSafeArea())
                }
            }
            .onChange(of: appModel.state, initial: true) { _, state in
                if case .ready(let connection) = state { shownConnection = connection }
            }
        }
    }

    private var isLocked: Bool { appModel.state == .locked }

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
            appModel: appModel,
            unpairing: environment.unpairing
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
    private let documents: WorkspaceDocuments
    private let canEdit: Bool
    private let appModel: AppModel
    private let deviceID: UUID

    init(
        appModel: AppModel, environment: AppEnvironment, connection: ServerConnection,
        workspace: WorkspacesModel.Row
    ) {
        let documents = WorkspaceDocuments(
            workspaceID: workspace.id, connection: connection, store: environment.store,
            server: environment.documents
        )
        // A role this app does not know may only look.
        let canEdit = workspace.role == .admin || workspace.role == .member
        _model = State(initialValue: DocumentsModel(
            documents: documents,
            uploads: environment.uploads,
            canScan: canEdit,
            camera: LiveScanCameraAccess(),
            openSettings: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            },
            onRevoked: { appModel.sessionRevoked(deviceID: connection.deviceID) },
            onMissingPairing: { appModel.connectionMissing() }
        ))
        _scanModel = State(initialValue: ScanFlowModel(workspaceID: workspace.id, uploads: environment.uploads))
        title = workspace.name
        self.documents = documents
        self.canEdit = canEdit
        self.appModel = appModel
        deviceID = connection.deviceID
    }

    var body: some View {
        DocumentsView(model: model, scanModel: scanModel, title: title) { documentID in
            ReviewScreen(
                documentID: documentID, documents: documents, canEdit: canEdit, appModel: appModel,
                deviceID: deviceID
            )
        }
    }
}

private struct ReviewScreen: View {
    @State private var model: ReviewModel

    init(documentID: UUID, documents: WorkspaceDocuments, canEdit: Bool, appModel: AppModel, deviceID: UUID) {
        _model = State(initialValue: ReviewModel(
            documentID: documentID,
            documents: documents,
            canEdit: canEdit,
            onRevoked: { appModel.sessionRevoked(deviceID: deviceID) },
            onMissingPairing: { appModel.connectionMissing() }
        ))
    }

    var body: some View {
        ReviewView(model: model)
    }
}
