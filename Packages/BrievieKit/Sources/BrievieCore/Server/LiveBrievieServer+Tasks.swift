import BrievieAPI
import Foundation
import OpenAPIRuntime

/// The tasks of a workspace: the open ones, ticking off and reopening (phase 1c).
extension LiveBrievieServer {
    public func openTasks(in scope: DocumentScope) async throws -> [WorkspaceTask] {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.listTasks(
                path: .init(workspaceId: scope.workspaceID.apiString), query: .init(status: "open")
            )
            switch output {
            case let .ok(response):
                return try response.body.json.map(WorkspaceTask.init(task:))
            case .unauthorized:
                throw ServerError.unauthorized
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .unprocessableContent(response):
                throw ServerError(status: 422, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func completeTask(_ id: UUID, in scope: DocumentScope) async throws -> WorkspaceTask {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.completeTask(
                path: .init(workspaceId: scope.workspaceID.apiString, taskId: id.apiString)
            )
            switch output {
            case let .ok(response):
                return try WorkspaceTask(task: response.body.json)
            case .unauthorized:
                throw ServerError.unauthorized
            case let .forbidden(response):
                throw ServerError(status: 403, code: try? response.body.json.code)
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func reopenTask(_ id: UUID, in scope: DocumentScope) async throws -> WorkspaceTask {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.reopenTask(
                path: .init(workspaceId: scope.workspaceID.apiString, taskId: id.apiString)
            )
            switch output {
            case let .ok(response):
                return try WorkspaceTask(task: response.body.json)
            case .unauthorized:
                throw ServerError.unauthorized
            case let .forbidden(response):
                throw ServerError(status: 403, code: try? response.body.json.code)
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }
}

private extension WorkspaceTask {
    init(task: Components.Schemas.TaskItemOut) throws(ServerError) {
        guard let id = UUID(uuidString: task.id) else { throw .incompatible }
        var documentID: UUID?
        if let text = task.documentId {
            guard let id = UUID(uuidString: text) else { throw .incompatible }
            documentID = id
        }
        self.init(
            id: id, type: task._type, description: task.description,
            deadline: task.deadline.flatMap(CalendarDate.init(iso:)), isDone: task.status == "done",
            documentID: documentID, sender: task.sender
        )
    }
}
