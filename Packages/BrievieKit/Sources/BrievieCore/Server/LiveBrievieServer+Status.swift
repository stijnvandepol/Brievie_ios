import BrievieAPI
import Foundation

/// Letter status (host PR #50): "Brief afhandelen", "Wacht op reactie" and "Uitstellen". A server before that
/// answers 404 without a Brievie code (`http_404`, read as "not supported").
extension LiveBrievieServer {
    public func handleDocument(
        _ id: UUID, taskIDs: [UUID], paymentsConfirmed: Bool, in scope: DocumentScope
    ) async throws -> DocumentDetail {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.handleDocument(
                path: .init(workspaceId: scope.workspaceID.apiString, documentId: id.apiString),
                body: .json(.init(paymentsConfirmed: paymentsConfirmed, taskIds: taskIDs.map(\.apiString)))
            )
            switch output {
            case let .ok(response):
                return try DocumentDetail(document: response.body.json)
            case let .badRequest(response):
                throw ServerError(status: 400, code: try? response.body.json.code)
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
            case let .forbidden(response):
                throw ServerError(status: 403, code: try? response.body.json.code)
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .conflict(response):
                throw ServerError(status: 409, code: try? response.body.json.code)
            case let .contentTooLarge(response):
                throw ServerError(status: 413, code: try? response.body.json.code)
            case let .unsupportedMediaType(response):
                throw ServerError(status: 415, code: try? response.body.json.code)
            case let .unprocessableContent(response):
                throw ServerError(status: 422, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func setTaskWaiting(
        _ id: UUID, until: CalendarDate?, in scope: DocumentScope
    ) async throws -> WorkspaceTask {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.setTaskWaiting(
                path: .init(workspaceId: scope.workspaceID.apiString, taskId: id.apiString),
                body: .json(.init(until: until?.iso))
            )
            switch output {
            case let .ok(response):
                return try WorkspaceTask(task: response.body.json)
            case let .badRequest(response):
                throw ServerError(status: 400, code: try? response.body.json.code)
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
            case let .forbidden(response):
                throw ServerError(status: 403, code: try? response.body.json.code)
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .conflict(response):
                throw ServerError(status: 409, code: try? response.body.json.code)
            case let .contentTooLarge(response):
                throw ServerError(status: 413, code: try? response.body.json.code)
            case let .unsupportedMediaType(response):
                throw ServerError(status: 415, code: try? response.body.json.code)
            case let .unprocessableContent(response):
                throw ServerError(status: 422, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func snoozeTask(_ id: UUID, until: CalendarDate?, in scope: DocumentScope) async throws -> WorkspaceTask {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.snoozeTask(
                path: .init(workspaceId: scope.workspaceID.apiString, taskId: id.apiString),
                body: .json(.init(until: until?.iso))
            )
            switch output {
            case let .ok(response):
                return try WorkspaceTask(task: response.body.json)
            case let .badRequest(response):
                throw ServerError(status: 400, code: try? response.body.json.code)
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
            case let .forbidden(response):
                throw ServerError(status: 403, code: try? response.body.json.code)
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .conflict(response):
                throw ServerError(status: 409, code: try? response.body.json.code)
            case let .contentTooLarge(response):
                throw ServerError(status: 413, code: try? response.body.json.code)
            case let .unsupportedMediaType(response):
                throw ServerError(status: 415, code: try? response.body.json.code)
            case let .unprocessableContent(response):
                throw ServerError(status: 422, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }
}

/// A letter's status fields (host PR #50); a server before that leaves all three out, which reads as no status.
struct LetterStatusFields {
    var letterStatus: String?
    var overdue: Bool?
    var waitingUntil: String?
}

extension ConfirmedTask {
    init(task: Components.Schemas.TaskOut) throws(ServerError) {
        guard let taskID = UUID(uuidString: task.id) else { throw .incompatible }
        var assignedToID: UUID?
        if let text = task.assignedToId {
            guard let id = UUID(uuidString: text) else { throw .incompatible }
            assignedToID = id
        }
        self.init(
            id: taskID, type: task._type, description: task.description,
            deadline: task.deadline.flatMap(CalendarDate.init(iso:)), deadlineSource: task.deadlineSource,
            deadlineQuote: task.deadlineQuote, isDone: task.status == "done",
            createdByAI: task.createdByAi ?? false, amount: task.amount.flatMap(TaskAmount.parse(api:)),
            termQuote: task.termQuote ?? "", assignedToID: assignedToID,
            assignedToName: task.assignedToName ?? "",
            permissions: TaskPermissions(take: task.canTake, handOver: task.canHandOver, release: task.canRelease),
            waitingUntil: task.waitingUntil.flatMap(CalendarDate.init(iso:)), waitOver: task.waitOver ?? false,
            snoozedUntil: task.snoozedUntil.flatMap(CalendarDate.init(iso:))
        )
    }
}
