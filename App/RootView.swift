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

/// The paired app: the screens of the current workspace, with the settings under "Meer".
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
            currentWorkspace: environment.currentWorkspace,
            reminders: WorkspaceReminders(reminders: environment.reminders, openSettings: openSystemSettings)
        ))
        self.appModel = appModel
        self.environment = environment
        self.connection = connection
    }

    var body: some View {
        WorkspaceRootView(model: model, warning: appModel.noPasscodeWarning) { workspace in
            WorkspaceScreen(
                appModel: appModel, environment: environment, connection: connection, workspace: workspace,
                workspaces: model, warning: appModel.noPasscodeWarning
            )
            // Another workspace (or another role in it) is another post: new models, nothing of the old one kept,
            // and the screens start on "Mijn post" again.
            .id(InboxIdentity(workspace: workspace.id, canEdit: WorkspaceScreen.canEdit(workspace)))
        }
        // This screen stays in the view tree while locked: every unlock after the first loads the list again, and
        // that load syncs the calendars and checks calendar access (the first unlock loads when the screen
        // appears). So each unlock syncs every workspace once.
        .onChange(of: appModel.state) { old, new in
            if old == .locked, case .ready = new { model.retry() }
            showTappedReminder()
        }
        // A tapped reminder shows its workspace once the app is open and the workspaces are known; its letter is
        // opened by that workspace's post (`DocumentsScreen`).
        .onChange(of: environment.reminderRouter.target, initial: true) { showTappedReminder() }
        .onChange(of: model.state) { showTappedReminder() }
    }

    private func showTappedReminder() {
        let router = environment.reminderRouter
        guard case .ready = appModel.state, let target = router.target, !model.rows.isEmpty else { return }
        // A workspace this phone no longer has, or a task without a letter: the app just opens.
        if !model.show(target) || target.documentID == nil { router.finish() }
    }
}

private struct InboxIdentity: Hashable {
    let workspace: UUID
    let canEdit: Bool
}

/// The screens of one workspace: the root of the paired app. Owns their models for as long as it shows this
/// workspace.
private struct WorkspaceScreen: View {
    @State private var screens: WorkspaceScreens
    private let workspaces: WorkspacesModel
    private let warning: String?
    private let documents: WorkspaceDocuments
    private let canEdit: Bool
    private let appModel: AppModel
    private let deviceID: UUID
    private let onTasksChanged: @MainActor () -> Void
    private let reminderRouter: ReminderRouter
    private let workspaceID: UUID

    /// A role this app does not know may only look.
    static func canEdit(_ workspace: WorkspacesModel.Row) -> Bool {
        workspace.role == .admin || workspace.role == .member
    }

    init(
        appModel: AppModel, environment: AppEnvironment, connection: ServerConnection,
        workspace: WorkspacesModel.Row, workspaces: WorkspacesModel, warning: String?
    ) {
        let documents = WorkspaceDocuments(
            workspaceID: workspace.id, connection: connection, store: environment.store,
            server: environment.documents, onRevoked: environment.revocations.revoked
        )
        let canEdit = Self.canEdit(workspace)
        let workspaceID = workspace.id
        let onTasksChanged: @MainActor () -> Void = { environment.tasksChanged(in: workspaceID) }
        let onRevoked: @MainActor () -> Void = { appModel.sessionRevoked(deviceID: connection.deviceID) }
        let onMissingPairing: @MainActor () -> Void = { appModel.connectionMissing() }
        _screens = State(initialValue: WorkspaceScreens(
            documents: documents, uploads: environment.uploads, canScan: canEdit, camera: LiveScanCameraAccess(),
            openSettings: openSystemSettings, onTasksChanged: onTasksChanged, onRevoked: onRevoked,
            onMissingPairing: onMissingPairing
        ))
        self.workspaces = workspaces
        self.warning = warning
        self.documents = documents
        self.canEdit = canEdit
        self.appModel = appModel
        deviceID = connection.deviceID
        self.onTasksChanged = onTasksChanged
        reminderRouter = environment.reminderRouter
        self.workspaceID = workspaceID
    }

    var body: some View {
        WorkspaceTabsView(screens: screens, warning: warning) { documentID, list in
            ReviewScreen(
                documentID: documentID, documents: documents, canEdit: canEdit, appModel: appModel,
                // Whichever list found the trash first: a letter opened from Taken or Blijft liggen (the Inbox's
                // model, maybe not loaded yet) still offers "Verwijderen".
                deviceID: deviceID, onTasksChanged: onTasksChanged,
                trashAvailable: screens.tabs.hasTrash || list.hasTrash,
                onTrashed: { [list] id in Task { await list.didTrash(id) } },
                onRead: { [list] in list.didRead(documentID) }
            )
        } compare: { pairID, list in
            DuplicateScreen(
                pairID: pairID, documents: documents, canEdit: canEdit, persons: list.persons, labels: list.labels,
                appModel: appModel, deviceID: deviceID,
                // `didMerge` lets the calendar follow (a twin task completed, the other letter's tasks left).
                onMerged: { [list] otherID in Task { await list.didMerge(trashed: otherID) } },
                onDismissed: { [list] in Task { await list.didDismissDuplicate() } },
                onDecidedElsewhere: { [list] in Task { await list.didFindPairDecided() } }
            )
        } pill: {
            WorkspacePillButton(model: workspaces)
        } settings: {
            SettingsView(model: workspaces)
        }
        // A tapped reminder of this workspace opens its letter, once the app is open (never behind the lock).
        .onChange(of: reminderRouter.target, initial: true) { openTappedLetter() }
        .onChange(of: appModel.state) { openTappedLetter() }
    }

    /// The letter opens on the start tab ("Mijn post", or the Inbox on an older server).
    private func openTappedLetter() {
        guard case .ready = appModel.state, let target = reminderRouter.target, target.workspaceID == workspaceID,
              let documentID = target.documentID
        else { return }
        screens.tabs.showStart()
        let list = screens.tabs.startTab == .myPost ? screens.myPost : screens.inbox
        list.openedDocument = documentID
        reminderRouter.finish()
    }
}

private struct ReviewScreen: View {
    @State private var model: ReviewModel

    init(
        documentID: UUID, documents: WorkspaceDocuments, canEdit: Bool, appModel: AppModel, deviceID: UUID,
        onTasksChanged: @escaping @MainActor () -> Void, trashAvailable: Bool,
        onTrashed: @escaping @MainActor (UUID) -> Void, onRead: @escaping @MainActor () -> Void
    ) {
        let model = ReviewModel(
            documentID: documentID,
            documents: documents,
            canEdit: canEdit,
            trashAvailable: trashAvailable,
            onRevoked: { appModel.sessionRevoked(deviceID: deviceID) },
            onMissingPairing: { appModel.connectionMissing() }
        )
        // After a confirm and after ticking off a task (also of the confirmed letter): the calendar follows.
        model.onTasksChanged = onTasksChanged
        // In the trash now: the post list offers the undo.
        model.onTrashed = onTrashed
        // Opened: the list's row is read at once, the menu's numbers follow.
        model.onRead = onRead
        _model = State(initialValue: model)
    }

    var body: some View {
        ReviewView(model: model)
    }
}

/// The compare screen of a pair in "Dubbel?". A merge or dismiss is reported to the post list, which reloads.
private struct DuplicateScreen: View {
    @State private var model: DuplicateModel

    init(
        pairID: UUID, documents: WorkspaceDocuments, canEdit: Bool, persons: [Person], labels: [DocumentLabel],
        appModel: AppModel, deviceID: UUID, onMerged: @escaping @MainActor (UUID) -> Void,
        onDismissed: @escaping @MainActor () -> Void, onDecidedElsewhere: @escaping @MainActor () -> Void
    ) {
        _model = State(initialValue: DuplicateModel(
            pairID: pairID, documents: documents, canEdit: canEdit, persons: persons, labels: labels,
            onMerged: onMerged, onDismissed: onDismissed, onDecidedElsewhere: onDecidedElsewhere,
            onRevoked: { appModel.sessionRevoked(deviceID: deviceID) },
            onMissingPairing: { appModel.connectionMissing() }
        ))
    }

    var body: some View {
        DuplicateView(model: model)
    }
}

/// Opens Brievie's page in the Settings app (camera or calendar access was refused).
@MainActor
private func openSystemSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
    }
}
