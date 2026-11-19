import BrievieCore
import BrievieUI
import FeatureDocuments
import FeaturePairing
import FeatureWorkspace
import SwiftUI

/// Switches on `AppModel.state`. While the app is not active, `PrivacyCoverWindow` (a window above this one and
/// everything it presents) hides it.
struct RootView: View {
    let appModel: AppModel
    let environment: AppEnvironment

    @Environment(\.scenePhase) private var scenePhase
    /// The pairing whose screens are in the view tree (also while locked); `nil` until the first unlock.
    @State private var shownConnection: ServerConnection?
    /// The sheet of a `brievie://server` link. Made by `BrievieApp`, which also asks it for the privacy cover.
    let linkModel: ServerLinkModel

    var body: some View {
        content
            .tint(BrievieColor.brand)
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
            // A deadline in the calendar links to `brievie://task/<id>`. That link (and any other that is not a
            // server link) only brings the app to the foreground: the lock and the screens follow from the
            // activation, nothing is read from it. A `brievie://server` link opens the link sheet; nothing is
            // contacted until the user taps "Server zoeken" there.
            .onOpenURL { url in
                guard ServerLink.isServerLink(url) else { return }
                linkModel.receive(url, appState: appModel.state)
            }
            .onChange(of: appModel.state) { _, state in
                linkModel.appStateChanged(state)
            }
            .sheet(isPresented: Binding(
                get: { linkModel.presentation != nil },
                set: { isPresented in
                    if !isPresented { linkModel.dismiss() }
                }
            )) {
                ServerLinkView(model: linkModel)
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
            PairingScreen(
                appModel: appModel, environment: environment, notice: notice,
                closesScanner: linkModel.presentation != nil
            )
        } else {
            ZStack {
                if let connection = shownConnection {
                    PairedScreen(appModel: appModel, environment: environment, connection: connection)
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
}

private struct PairingScreen: View {
    @State private var model: PairingModel
    private let notice: String?
    private let closesScanner: Bool

    init(appModel: AppModel, environment: AppEnvironment, notice: String?, closesScanner: Bool) {
        _model = State(initialValue: PairingModel(
            service: PairingService(server: environment.server, store: environment.store),
            camera: LiveCameraAccess(),
            deviceName: { UIDevice.current.name },
            openSettings: openSystemSettings,
            onPaired: { appModel.didPair($0) }
        ))
        self.notice = notice
        self.closesScanner = closesScanner
    }

    var body: some View {
        PairingView(model: model, notice: notice, closesScanner: closesScanner)
    }
}

/// The paired app: the inbox of the current workspace, with the settings behind it.
private struct PairedScreen: View {
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
            unpairing: environment.unpairing,
            calendar: WorkspaceCalendar(
                sync: environment.calendarSync,
                settings: environment.calendarSettings,
                openSettings: openSystemSettings,
                // The switches sync themselves after this (`CalendarSettingModel.refresh()`).
                didLoad: { rows in
                    environment.workspaceNames.replace(
                        with: Dictionary(rows.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
                    )
                }
            ),
            currentWorkspace: environment.currentWorkspace
        ))
        self.appModel = appModel
        self.environment = environment
        self.connection = connection
    }

    var body: some View {
        WorkspaceRootView(model: model, warning: appModel.noPasscodeWarning) { workspace in
            DocumentsScreen(
                appModel: appModel, environment: environment, connection: connection, workspace: workspace,
                workspaceName: model.showsWorkspaceName ? workspace.name : nil,
                warning: appModel.noPasscodeWarning
            )
            // Another workspace (or another role in it) is another post: new models, nothing of the old one kept.
            .id(InboxIdentity(workspace: workspace.id, canEdit: DocumentsScreen.canEdit(workspace)))
        }
        // This screen stays in the view tree while locked: every unlock after the first loads the list again, and
        // that load syncs the calendars and checks calendar access (the first unlock loads when the screen
        // appears). So each unlock syncs every workspace once.
        .onChange(of: appModel.state) { old, new in
            if old == .locked, case .ready = new { model.retry() }
        }
    }
}

private struct InboxIdentity: Hashable {
    let workspace: UUID
    let canEdit: Bool
}

/// The post of one workspace: the root of the paired app. Owns its models for as long as it shows this workspace.
private struct DocumentsScreen: View {
    @State private var model: DocumentsModel
    @State private var scanModel: ScanFlowModel
    private let title: String
    private let workspaceName: String?
    private let warning: String?
    private let documents: WorkspaceDocuments
    private let canEdit: Bool
    private let appModel: AppModel
    private let deviceID: UUID
    private let onTasksChanged: @MainActor () -> Void

    /// A role this app does not know may only look.
    static func canEdit(_ workspace: WorkspacesModel.Row) -> Bool {
        workspace.role == .admin || workspace.role == .member
    }

    init(
        appModel: AppModel, environment: AppEnvironment, connection: ServerConnection,
        workspace: WorkspacesModel.Row, workspaceName: String?, warning: String?
    ) {
        let documents = WorkspaceDocuments(
            workspaceID: workspace.id, connection: connection, store: environment.store,
            server: environment.documents
        )
        let canEdit = Self.canEdit(workspace)
        _model = State(initialValue: DocumentsModel(
            documents: documents,
            uploads: environment.uploads,
            canScan: canEdit,
            camera: LiveScanCameraAccess(),
            openSettings: openSystemSettings,
            onRevoked: { appModel.sessionRevoked(deviceID: connection.deviceID) },
            onMissingPairing: { appModel.connectionMissing() }
        ))
        _scanModel = State(initialValue: ScanFlowModel(workspaceID: workspace.id, uploads: environment.uploads))
        title = workspace.name
        self.workspaceName = workspaceName
        self.warning = warning
        self.documents = documents
        self.canEdit = canEdit
        self.appModel = appModel
        deviceID = connection.deviceID
        let workspaceID = workspace.id
        onTasksChanged = { environment.syncCalendar(of: workspaceID) }
    }

    var body: some View {
        DocumentsView(
            model: model, scanModel: scanModel, title: title, workspaceName: workspaceName, warning: warning
        ) { documentID in
            ReviewScreen(
                documentID: documentID, documents: documents, canEdit: canEdit, appModel: appModel,
                deviceID: deviceID, onTasksChanged: onTasksChanged
            )
        }
    }
}

private struct ReviewScreen: View {
    @State private var model: ReviewModel

    init(
        documentID: UUID, documents: WorkspaceDocuments, canEdit: Bool, appModel: AppModel, deviceID: UUID,
        onTasksChanged: @escaping @MainActor () -> Void
    ) {
        let model = ReviewModel(
            documentID: documentID,
            documents: documents,
            canEdit: canEdit,
            onRevoked: { appModel.sessionRevoked(deviceID: deviceID) },
            onMissingPairing: { appModel.connectionMissing() }
        )
        // After a confirm and after ticking off a task (also of the confirmed letter): the calendar follows.
        model.onTasksChanged = onTasksChanged
        _model = State(initialValue: model)
    }

    var body: some View {
        ReviewView(model: model)
    }
}

/// Opens Brievie's page in the Settings app (camera or calendar access was refused).
@MainActor
private func openSystemSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
    }
}
