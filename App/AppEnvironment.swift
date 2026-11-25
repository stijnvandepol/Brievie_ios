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
    /// Where every call of the paired app reports a 401 `not_authenticated`: ends the session at once.
    let revocations: RevocationRelay

    /// - Parameters:
    ///   - shared: what `AppModel` shares (it clears the calendar switches, the current workspace and the reminders
    ///     with the pairing, and removes the calendars after a revocation).
    @MainActor
    static func live(
        store: ConnectionStore, server: LiveBrievieServer, shared: AppShared
    ) -> AppEnvironment {
        let calendar = shared.calendar
        let transport = BackgroundUploadTransport(trustProvider: StoredConnectionTrustProvider(store: store))
        // Created at launch, also in the background: the system delivers upload events to this session.
        transport.activate()
        let uploads = UploadCoordinator(
            store: UploadQueueStore(directory: uploadsDirectory),
            transport: transport,
            connection: { try store.load().map { ($0.connection, $0.token) } },
            onRevoked: shared.revocations.revoked
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
            reminderRouter: shared.reminderRouter, revocations: shared.revocations
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
    let revocations: RevocationRelay
}

/// The one place a 401 `not_authenticated` goes, from any call of the paired app (documents, tasks for the calendar
/// and the reminders, uploads): `AppModel.sessionRevoked(deviceID:)`. Made before the app model, so the calendar and
/// the reminders, which are made first, can hold it; the app connects it once the model exists.
final class RevocationRelay: Sendable {
    private let target = Mutex<(@Sendable (UUID) async -> Void)?>(nil)

    func connect(_ handler: @escaping @Sendable (UUID) async -> Void) {
        target.withLock { $0 = handler }
    }

    @Sendable func revoked(_ deviceID: UUID) async {
        await target.withLock { $0 }?(deviceID)
    }
}

/// The calendar parts the app model and the environment share. Made before both: `AppModel` needs the sync to
/// remove the calendars after a revocation.
struct AppCalendar {
    let settings: any CalendarSettings
    let sync: CalendarSync
    let workspaceNames: WorkspaceNames

    init(
        store: ConnectionStore, server: LiveBrievieServer, settings: any CalendarSettings, revocations: RevocationRelay
    ) {
        let workspaceNames = WorkspaceNames()
        self.settings = settings
        self.workspaceNames = workspaceNames
        sync = CalendarSync(
            store: EventKitCalendarStore(),
            settings: settings,
            // The calendar follows "Welke taken": the member's own tasks by default, or all they may see.
            tasks: Self.phoneTasks(store: store, server: server, revocations: revocations) { workspace in
                settings.taskPart(for: workspace)
            },
            workspaceName: { workspaceNames.name(of: $0) },
            typeTitle: { TaskTypeName.label(for: $0) },
            today: { CalendarDate(Date(), in: .current) }
        )
    }

    /// The open tasks of a workspace the phone follows, through the stored pairing: for the calendar (`part` per
    /// workspace) and the reminders (always the member's own). A server before "Mijn taken" gives every open task.
    static func phoneTasks(
        store: ConnectionStore, server: LiveBrievieServer, revocations: RevocationRelay,
        part: @escaping @Sendable (UUID) -> MyTasksPart = { _ in .mine }
    ) -> CalendarSync.TaskSource {
        { workspace in
            guard let stored = try store.load() else { throw DocumentsError.missingPairing }
            return try await WorkspaceDocuments(
                workspaceID: workspace, connection: stored.connection, store: store, server: server,
                onRevoked: revocations.revoked
            ).phoneTasks(part(workspace))
        }
    }

    /// The member's own open tasks for the reminders, with the ones that wait for a reply ("Wachten voorbij").
    static func reminderTasks(
        store: ConnectionStore, server: LiveBrievieServer, revocations: RevocationRelay
    ) -> CalendarSync.TaskSource {
        { workspace in
            guard let stored = try store.load() else { throw DocumentsError.missingPairing }
            return try await WorkspaceDocuments(
                workspaceID: workspace, connection: stored.connection, store: store, server: server,
                onRevoked: revocations.revoked
            ).reminderTasks()
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
