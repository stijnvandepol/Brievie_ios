import BrievieCore
import Foundation
import Observation

/// Loads the workspaces of the paired user, decides which one the inbox shows, and notices when the server no
/// longer knows this device.
@MainActor
@Observable
public final class WorkspacesModel {
    public struct Row: Equatable, Identifiable {
        public let id: UUID
        public let name: String
        public let kind: WorkspaceSummary.Kind
        public let kindLabel: String
        /// `nil` for a role this app does not know: no badge.
        public let roleLabel: String?
        /// What the user may do in this workspace; `.unknown` reads as "may only look".
        public var role: WorkspaceSummary.Role = .unknown
    }

    public enum State: Equatable {
        case loading
        case loaded([Row])
        case failed(message: String)
    }

    /// What the app's root screen shows.
    public enum Root: Equatable {
        case loading
        /// The first load failed: the error with "Opnieuw proberen".
        case failed(message: String)
        /// The user has no workspace.
        case empty
        /// The post of this workspace.
        case inbox(Row)
    }

    public private(set) var state: State = .loading

    /// The workspace the inbox shows: the one shown last under this pairing while the server still lists it,
    /// else the first the server lists. `nil` until the list loaded, and when it is empty.
    public private(set) var currentWorkspaceID: UUID?

    public var root: Root {
        switch state {
        case .loading: .loading
        case .failed(let message): .failed(message: message)
        case .loaded(let rows): rows.first { $0.id == currentWorkspaceID }.map(Root.inbox) ?? .empty
        }
    }

    /// The loaded workspaces; empty while loading or after a failed first load.
    public var rows: [Row] {
        if case .loaded(let rows) = state { return rows }
        return []
    }

    /// More than one workspace: the inbox says which one it shows. With one the user never sees the word.
    public var showsWorkspaceName: Bool { rows.count > 1 }

    /// The settings are pushed on the root screen.
    public var isShowingSettings = false
    /// The workspace picker (the sheet of the workspace pill) is open.
    public var isShowingPicker = false

    /// The workspace the post shows; `nil` while loading, after a failed load, and without workspaces.
    public var currentRow: Row? { rows.first { $0.id == currentWorkspaceID } }

    /// There is another workspace to go to: the pill is a button with a chevron. With one it is a label.
    public var canSwitch: Bool { rows.count > 1 }
    /// "Meldingen voor termijnen"; `nil` without reminder support.
    public let reminderModel: ReminderSettingModel?

    /// The "Ontkoppelen" confirmation is on screen.
    public var isConfirmingUnpair = false
    /// Scans waiting in the upload queue when the user asked to unpair; the confirmation says they go.
    public private(set) var queuedScanCount = 0
    /// At least one calendar switch was on when the user asked to unpair: the confirmation also offers
    /// "Ontkoppelen en agenda's verwijderen".
    public private(set) var offersCalendarRemoval = false
    /// Unpairing is running: the button is disabled and shows progress.
    public var isUnpairing: Bool { appModel.isUnpairing }

    /// The confirmation's message, with the number of scans that will be deleted when there are any.
    public var unpairMessage: String {
        queuedScanCount > 0 ? WorkspaceStrings.unpairMessageQueued(queuedScanCount) : WorkspaceStrings.unpairMessage
    }

    /// Host of the first stored server address, for the Server section; `nil` if it has none.
    public var serverAddress: String? { connection.urls.first?.host() }
    /// The paired user's name, as stored at pairing.
    public var userName: String { connection.userName }

    private let connection: ServerConnection
    private let store: ConnectionStore
    private let server: any BrievieServer
    private let appModel: AppModel
    private let unpairing: Unpairing
    private let calendar: WorkspaceCalendar?
    private let currentWorkspace: any CurrentWorkspaceStore
    private let reminders: DeadlineReminders?
    /// The calendar switch per workspace of the last load; kept across reloads.
    private var calendarModels: [UUID: CalendarSettingModel] = [:]
    /// The load started by `retry()`; `stop()` cancels it when the screen goes away. Tests await it.
    @ObservationIgnored private(set) var retryTask: Task<Void, Never>?
    /// Counts the queue before the confirmation opens. Tests await it.
    @ObservationIgnored private(set) var unpairCountTask: Task<Void, Never>?
    /// The reminders' refresh after a load. Tests await it.
    @ObservationIgnored private(set) var reminderTask: Task<Void, Never>?

    /// - Parameter calendar: the calendar switches; `nil` shows none.
    /// - Parameter currentWorkspace: where the workspace the inbox shows is remembered across launches.
    /// - Parameter reminders: the deadline reminders, refreshed after every load; `nil` shows no switch.
    public init(
        connection: ServerConnection, store: ConnectionStore, server: any BrievieServer, appModel: AppModel,
        unpairing: Unpairing, calendar: WorkspaceCalendar? = nil,
        currentWorkspace: any CurrentWorkspaceStore = InMemoryCurrentWorkspaceStore(),
        reminders: WorkspaceReminders? = nil
    ) {
        self.connection = connection
        self.store = store
        self.server = server
        self.appModel = appModel
        self.unpairing = unpairing
        self.calendar = calendar
        self.currentWorkspace = currentWorkspace
        self.reminders = reminders?.reminders
        reminderModel = reminders.map { ReminderSettingModel(reminders: $0.reminders, openSettings: $0.openSettings) }
        reminderModel?.calendarIsOn = { [weak self] in
            self?.calendarModels.values.contains { $0.isOn } ?? false
        }
    }

    /// Shows the post of `workspace` (one of the loaded list) and remembers it for the next launch.
    public func select(_ workspace: UUID) {
        guard rows.contains(where: { $0.id == workspace }) else { return }
        currentWorkspaceID = workspace
        currentWorkspace.remember(workspace, forDevice: connection.deviceID)
    }

    /// The workspace pill: opens the picker, only when there is another workspace.
    public func showPicker() {
        guard canSwitch else { return }
        isShowingPicker = true
    }

    /// A workspace chosen in the picker. The picker closes; the current one changes nothing else, another one
    /// becomes the shown workspace (whose screens start anew, on "Mijn post").
    public func choose(_ workspace: UUID) {
        isShowingPicker = false
        guard workspace != currentWorkspaceID else { return }
        isShowingSettings = false
        select(workspace)
    }

    /// What VoiceOver says for the pill: the workspace, and with more than one that another can be chosen.
    public func pillAccessibilityLabel(for row: Row) -> String {
        String(format: canSwitch ? WorkspaceStrings.pillSwitchFormat : WorkspaceStrings.pillFormat, row.name)
    }

    /// A tapped reminder: shows its workspace (closing the settings) when this phone still has it. `false` when the
    /// workspaces are not loaded or no longer list it: then nothing changes.
    @discardableResult
    public func show(_ target: ReminderTarget) -> Bool {
        guard rows.contains(where: { $0.id == target.workspaceID }) else { return false }
        isShowingSettings = false
        isShowingPicker = false
        select(target.workspaceID)
        return true
    }

    /// The "Zet termijnen in mijn agenda" switch of a loaded workspace; `nil` without calendar support.
    public func calendarModel(for workspace: UUID) -> CalendarSettingModel? {
        calendarModels[workspace]
    }

    /// The "Ontkoppelen" button: counts the waiting scans, then asks for confirmation.
    public func requestUnpair() {
        guard !isUnpairing, unpairCountTask == nil else { return }
        unpairCountTask = Task {
            queuedScanCount = await unpairing.queuedScanCount()
            offersCalendarRemoval = unpairing.hasCalendars
            isConfirmingUnpair = true
            unpairCountTask = nil
        }
    }

    /// The user confirmed; with `removingCalendars`, each workspace's own calendar goes too. `AppModel` owns the
    /// work and ignores a second tap.
    public func confirmUnpair(removingCalendars: Bool = false) {
        appModel.requestUnpair(removingCalendars ? unpairing.removingCalendars() : unpairing)
    }

    /// The app leaves the foreground: questions that name a workspace close (they would sit above the lock).
    public func sceneLeftForeground() {
        for model in calendarModels.values { model.sceneLeftForeground() }
    }

    /// For the retry button: loads again, tied to this model so that `stop()` can cancel it.
    public func retry() {
        retryTask?.cancel()
        retryTask = Task { await load() }
    }

    /// The screen went away: a load that is still running is no longer wanted.
    public func stop() {
        retryTask?.cancel()
        retryTask = nil
    }

    /// Tries the connection's URLs in order. A 401 means the device was revoked: the app returns to pairing.
    public func load() async {
        if case .failed = state { state = .loading }
        let token: String
        do {
            guard let stored = try store.load() else {
                appModel.connectionMissing()
                return
            }
            token = stored.token
        } catch {
            state = .failed(message: WorkspaceStrings.generic)
            return
        }

        switch await fetch(token: token) {
        case .workspaces(let workspaces):
            let rows = workspaces.map(Row.init(workspace:))
            updateCalendarModels(rows)
            chooseCurrent(in: rows)
            state = .loaded(rows)
            // The app learns the names first: a sync names the calendar after its workspace.
            calendar?.didLoad(rows)
            for model in calendarModels.values { model.refresh() }
            refreshReminders(workspaces: rows.map(\.id))
        case .revoked:
            appModel.sessionRevoked(deviceID: connection.deviceID)
        case .cancelled:
            break
        case .failed(let message):
            // A list that is already on screen stays; only the first load turns into an error.
            if case .loaded = state { return }
            state = .failed(message: message)
        }
    }

    /// Keeps the current workspace while the list still has it; otherwise the one remembered for this pairing,
    /// else the first. A list without workspaces chooses none and leaves the remembered one alone.
    private func chooseCurrent(in rows: [Row]) {
        let wanted = currentWorkspaceID ?? currentWorkspace.workspace(forDevice: connection.deviceID)
        guard let chosen = rows.first(where: { $0.id == wanted })?.id ?? rows.first?.id else {
            currentWorkspaceID = nil
            return
        }
        currentWorkspaceID = chosen
        if currentWorkspace.workspace(forDevice: connection.deviceID) != chosen {
            currentWorkspace.remember(chosen, forDevice: connection.deviceID)
        }
    }

    /// The workspaces this phone is paired to now: their reminders follow, those of a workspace that is gone go.
    private func refreshReminders(workspaces: [UUID]) {
        guard let reminders else { return }
        reminderModel?.refresh()
        let previous = reminderTask
        reminderTask = Task {
            await previous?.value
            await reminders.reschedule(workspaces: workspaces)
        }
    }

    private func updateCalendarModels(_ rows: [Row]) {
        guard let calendar else { return }
        var models: [UUID: CalendarSettingModel] = [:]
        for row in rows {
            if let existing = calendarModels[row.id], existing.workspaceName == row.name {
                models[row.id] = existing
            } else {
                models[row.id] = CalendarSettingModel(
                    workspaceID: row.id, workspaceName: row.name, sync: calendar.sync, settings: calendar.settings,
                    openSettings: calendar.openSettings
                )
            }
        }
        calendarModels = models
    }

    private enum Outcome {
        case workspaces([WorkspaceSummary])
        case revoked
        case cancelled
        case failed(message: String)
    }

    private func fetch(token: String) async -> Outcome {
        let trust = ServerTrust(caCertificateDER: connection.caCertificateDER)
        var sawUntrusted = false
        var sawForeign401 = false
        for url in connection.urls {
            do {
                return .workspaces(try await server.workspaces(at: url, trust: trust, token: token))
            } catch ServerError.unauthorized {
                return .revoked
            } catch ServerError.unreachable {
                continue
            } catch ServerError.untrusted {
                sawUntrusted = true
            } catch ServerError.other("http_401") {
                // Not the host's verdict (no `not_authenticated`): try the next address, never a revocation.
                sawForeign401 = true
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failed(message: WorkspaceStrings.generic)
            }
        }
        if Task.isCancelled { return .cancelled }
        if sawUntrusted { return .failed(message: WorkspaceStrings.notVerified) }
        return .failed(message: sawForeign401 ? WorkspaceStrings.generic : WorkspaceStrings.unreachable)
    }
}

extension WorkspacesModel.Row {
    init(workspace: WorkspaceSummary) {
        self.init(
            id: workspace.id,
            name: workspace.name,
            kind: workspace.kind,
            kindLabel: Self.label(for: workspace.kind),
            roleLabel: Self.label(for: workspace.role),
            role: workspace.role
        )
    }

    private static func label(for kind: WorkspaceSummary.Kind) -> String {
        switch kind {
        case .home: WorkspaceStrings.kindHome
        case .business: WorkspaceStrings.kindBusiness
        case .unknown: WorkspaceStrings.kindUnknown
        }
    }

    private static func label(for role: WorkspaceSummary.Role) -> String? {
        switch role {
        case .admin: WorkspaceStrings.roleAdmin
        case .member: WorkspaceStrings.roleMember
        case .viewer: WorkspaceStrings.roleViewer
        case .unknown: nil
        }
    }
}

extension WorkspacesModel.Row {
    /// SF Symbol for the workspace kind; a neutral one for a kind this app does not know.
    public var iconName: String {
        switch kind {
        case .home: "house.fill"
        case .business: "briefcase.fill"
        case .unknown: "square.grid.2x2.fill"
        }
    }

    /// "Thuis · Beheerder". The kind is left out when it only repeats the workspace name (a workspace
    /// called "Thuis" of kind home); just the kind when the role is unknown.
    public var subtitle: String {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let repeatsName = kindLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(normalizedName) == .orderedSame
        return [repeatsName ? nil : kindLabel, roleLabel].compactMap { $0 }.joined(separator: " · ")
    }
}
