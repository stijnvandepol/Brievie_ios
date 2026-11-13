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
        public let kindLabel: String
        /// `nil` for a role this app does not know: no badge.
        public let roleLabel: String?
    }

    public enum State: Equatable {
        case loading
        case loaded([Row])
        case failed(message: String)
    }

    public private(set) var state: State = .loading

    private let connection: ServerConnection
    private let store: ConnectionStore
    private let server: any BrievieServer
    private let appModel: AppModel

    public init(connection: ServerConnection, store: ConnectionStore, server: any BrievieServer, appModel: AppModel) {
        self.connection = connection
        self.store = store
        self.server = server
        self.appModel = appModel
    }

    /// Tries the connection's URLs in order. A 401 means the device was revoked: the app returns to pairing.
    public func load() async {
        if case .failed = state { state = .loading }
        let token: String
        do {
            guard let stored = try store.load() else {
                appModel.sessionRevoked()
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
            appModel.sessionRevoked()
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
            kindLabel: Self.label(for: workspace.kind),
            roleLabel: Self.label(for: workspace.role)
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
