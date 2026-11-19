import BrievieCore
import FeatureDocuments
import Foundation
import Synchronization

/// What the app talks to: the Keychain-backed connection store, the live server client and the upload queue.
struct AppEnvironment {
    let store: ConnectionStore
    let server: any BrievieServer
    let documents: any DocumentServer
    let launchFlag: any LaunchFlag
    let uploads: UploadCoordinator
    /// "Ontkoppelen": the live server, the upload queue and the calendar switches.
    let unpairing: Unpairing
    let calendarSettings: any CalendarSettings
    /// Deadlines in a calendar per workspace, on this phone.
    let calendarSync: CalendarSync
    /// The names of the workspaces loaded last: the calendars are named after them.
    let workspaceNames: WorkspaceNames
    /// Which workspace the inbox showed last, per pairing; shared with `AppModel`, which forgets it with the pairing.
    let currentWorkspace: any CurrentWorkspaceStore
    /// Deadline reminders on this phone; shared with `AppModel`, which forgets them with the pairing.
    let reminders: DeadlineReminders
    /// The reminder the user tapped, until the paired app showed it; the app delegate sets it.
    let reminderRouter: ReminderRouter

    /// - Parameters:
    ///   - shared: what `AppModel` shares (it clears the calendar switches, the current workspace and the reminders
    ///     with the pairing, and removes the calendars after a revocation).
    ///   - onRevoked: called when an upload finds that the server no longer knows this device.
    @MainActor
    static func live(
        store: ConnectionStore, server: LiveBrievieServer, shared: AppShared,
        onRevoked: @escaping @Sendable (UUID) async -> Void
    ) -> AppEnvironment {
        let calendar = shared.calendar
        let transport = BackgroundUploadTransport(trustProvider: StoredConnectionTrustProvider(store: store))
        // Created at launch, also in the background: the system delivers upload events to this session.
        transport.activate()
        let uploads = UploadCoordinator(
            store: UploadQueueStore(directory: uploadsDirectory),
            transport: transport,
            connection: { try store.load().map { ($0.connection, $0.token) } },
            onRevoked: onRevoked
        )
        AppDelegate.uploads = uploads
        Task { await uploads.run() }
        return AppEnvironment(
            store: store, server: server, documents: server, launchFlag: UserDefaultsLaunchFlag(), uploads: uploads,
            unpairing: Unpairing(
                server: server, uploads: uploads, calendarSettings: calendar.settings, calendarSync: calendar.sync
            ),
            calendarSettings: calendar.settings, calendarSync: calendar.sync, workspaceNames: calendar.workspaceNames,
            currentWorkspace: shared.currentWorkspace, reminders: shared.reminders,
            reminderRouter: shared.reminderRouter
        )
    }

    /// After a confirm or a ticked task in `workspace`: its calendar and the reminders follow.
    func tasksChanged(in workspace: UUID) {
        let sync = calendarSync
        let reminders = reminders
        Task { _ = await sync.sync(workspace: workspace) }
        Task { await reminders.reschedule() }
    }

    /// Scans waiting for upload. Not in a cache directory: the system may empty those.
    private static var uploadsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Uploads", directoryHint: .isDirectory)
    }
}

/// What the app model and the environment share, made before both: `AppModel` forgets the calendar switches, the
/// current workspace and the reminders with the pairing.
struct AppShared {
    let calendar: AppCalendar
    let currentWorkspace: any CurrentWorkspaceStore
    let reminders: DeadlineReminders
    /// The reminder the user tapped; the app delegate sets it.
    let reminderRouter: ReminderRouter
}

/// The calendar parts the app model and the environment share. Made before both: `AppModel` needs the sync to
/// remove the calendars after a revocation.
struct AppCalendar {
    let settings: any CalendarSettings
    let sync: CalendarSync
    let workspaceNames: WorkspaceNames

    init(store: ConnectionStore, server: LiveBrievieServer, settings: any CalendarSettings) {
        let workspaceNames = WorkspaceNames()
        self.settings = settings
        self.workspaceNames = workspaceNames
        sync = CalendarSync(
            store: EventKitCalendarStore(),
            settings: settings,
            tasks: Self.openTasks(store: store, server: server),
            workspaceName: { workspaceNames.name(of: $0) },
            typeTitle: { TaskTypeName.label(for: $0) },
            today: { CalendarDate(Date(), in: .current) }
        )
    }

    /// The open tasks of a workspace on the server, through the stored pairing: for the calendar and the reminders.
    static func openTasks(store: ConnectionStore, server: LiveBrievieServer) -> CalendarSync.TaskSource {
        { workspace in
            guard let stored = try store.load() else { throw DocumentsError.missingPairing }
            return try await WorkspaceDocuments(
                workspaceID: workspace, connection: stored.connection, store: store, server: server
            ).openTasks()
        }
    }
}

/// The names of the loaded workspaces, readable from any isolation.
final class WorkspaceNames: Sendable {
    private let names = Mutex<[UUID: String]>([:])

    func name(of workspace: UUID) -> String {
        names.withLock { $0[workspace] } ?? ""
    }

    func replace(with names: [UUID: String]) {
        self.names.withLock { $0 = names }
    }
}
