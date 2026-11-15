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

    /// Host of the first stored server address, for the Server section; `nil` if it has none.
    public var serverAddress: String? { connection.urls.first?.host() }
    /// The paired user's name, as stored at pairing.
    public var userName: String { connection.userName }

    private let connection: ServerConnection
    private let store: ConnectionStore
    private let server: any BrievieServer
    private let appModel: AppModel
    /// The load started by `retry()`; `stop()` cancels it when the screen goes away. Tests await it.
    @ObservationIgnored private(set) var retryTask: Task<Void, Never>?

    public init(connection: ServerConnection, store: ConnectionStore, server: any BrievieServer, appModel: AppModel) {
        self.connection = connection
        self.store = store
        self.server = server
        self.appModel = appModel
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
            state = .loaded(workspaces.map(Row.init(workspace:)))
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
