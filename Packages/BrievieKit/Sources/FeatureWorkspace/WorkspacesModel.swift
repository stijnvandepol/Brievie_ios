import BrievieCore
import Foundation
import Observation

/// Loads the workspaces of the paired user and notices when the server no longer knows this device.
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

    public private(set) var state: State = .loading

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
    /// The calendar switch per workspace of the last load; kept across reloads.
    private var calendarModels: [UUID: CalendarSettingModel] = [:]
    /// The load started by `retry()`; `stop()` cancels it when the screen goes away. Tests await it.
    @ObservationIgnored private(set) var retryTask: Task<Void, Never>?
    /// Counts the queue before the confirmation opens. Tests await it.
    @ObservationIgnored private(set) var unpairCountTask: Task<Void, Never>?

    /// - Parameter calendar: the calendar switches; `nil` shows none.
    public init(
        connection: ServerConnection, store: ConnectionStore, server: any BrievieServer, appModel: AppModel,
        unpairing: Unpairing, calendar: WorkspaceCalendar? = nil
    ) {
        self.connection = connection
        self.store = store
        self.server = server
        self.appModel = appModel
        self.unpairing = unpairing
        self.calendar = calendar
    }

    /// The "Zet deadlines in mijn agenda" switch of a loaded workspace; `nil` without calendar support.
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
            state = .loaded(rows)
            // The app learns the names first: a sync names the calendar after its workspace.
            calendar?.didLoad(rows)
            for model in calendarModels.values { model.refresh() }
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
        for url in connection.urls {
            do {
                return .workspaces(try await server.workspaces(at: url, trust: trust, token: token))
            } catch ServerError.unauthorized {
                return .revoked
            } catch ServerError.unreachable {
                continue
            } catch ServerError.untrusted {
                sawUntrusted = true
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failed(message: WorkspaceStrings.generic)
            }
        }
        if Task.isCancelled { return .cancelled }
        return .failed(message: sawUntrusted ? WorkspaceStrings.notVerified : WorkspaceStrings.unreachable)
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
