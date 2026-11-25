import BrievieAPI
import Foundation
import OpenAPIRuntime

/// "Mijn taken" (host PR #36): the member's own tasks, their counts, and picking up, handing over and dating a
/// task. A server before that answers 404 without a Brievie code (`http_404`, read as "not supported").
extension LiveBrievieServer {
    public func myTasks(part: MyTasksPart, status: MyTasksStatus, in scope: DocumentScope) async throws -> MyTasks {
        try await myTasks(part: part, status: status, includeWaiting: false, in: scope)
    }

    /// With `includeWaiting` the server adds the groups `waiting` and `snoozed` (host PR #50); without, an older
    /// caller never gets them. A server before that ignores the parameter.
    public func myTasks(
        part: MyTasksPart, status: MyTasksStatus, includeWaiting: Bool, in scope: DocumentScope
    ) async throws -> MyTasks {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.listMyTasks(
                path: .init(workspaceId: scope.workspaceID.apiString),
                query: .init(part: part.rawValue, status: status.rawValue, includeWaiting: includeWaiting ? true : nil)
            )
            switch output {
            case let .ok(response):
                return try MyTasks(answer: response.body.json)
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .unprocessableContent(response):
                throw ServerError(status: 422, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func myTaskCounts(in scope: DocumentScope) async throws -> MyTaskCounts {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.countMyTasks(path: .init(workspaceId: scope.workspaceID.apiString))
            switch output {
            case let .ok(response):
                let counts = try response.body.json
                return MyTaskCounts(
                    mine: counts.mine, overdue: counts.overdue, withinWeek: counts.withinWeek,
                    needsDate: counts.needsDate, toPickUp: counts.toPickUp, waiting: counts.waiting ?? 0,
                    snoozed: counts.snoozed ?? 0
                )
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    /// Gives the task to `user`, or releases it with `nil`.
    public func assignTask(_ id: UUID, to user: UUID?, in scope: DocumentScope) async throws -> WorkspaceTask {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.assignTask(
                path: .init(workspaceId: scope.workspaceID.apiString, taskId: id.apiString),
                body: .json(.init(userId: user?.apiString))
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
            case let .contentTooLarge(response):
                throw ServerError(status: 413, code: try? response.body.json.code)
            case let .unsupportedMediaType(response):
                throw ServerError(status: 415, code: try? response.body.json.code)
            case let .unprocessableContent(response):
                throw ServerError(status: 422, code: try? response.body.json.code)
            case .undocumented(409, _):
                // The server's coming rule (`task_taken`): someone else does the task already. Not in the
                // contract yet, so its body is not read; a 409 on this call can mean nothing else.
                throw ServerError.other("task_taken")
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    /// The people the task can be handed to: the members who may read its letter (names only).
    public func taskAssignees(_ id: UUID, in scope: DocumentScope) async throws -> [TaskAssignee] {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.listTaskAssignees(
                path: .init(workspaceId: scope.workspaceID.apiString, taskId: id.apiString)
            )
            switch output {
            case let .ok(response):
                return try response.body.json.map { person throws(ServerError) in
                    guard let id = UUID(uuidString: person.userId) else { throw .incompatible }
                    return TaskAssignee(id: id, name: person.name, isMe: person.isMe)
                }
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
            case let .forbidden(response):
                throw ServerError(status: 403, code: try? response.body.json.code)
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    /// Sets the deadline the user read in the letter ("Datum invullen"), or removes it with `nil`.
    public func setTaskDeadline(
        _ id: UUID, to deadline: CalendarDate?, in scope: DocumentScope
    ) async throws -> WorkspaceTask {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.setTaskDeadline(
                path: .init(workspaceId: scope.workspaceID.apiString, taskId: id.apiString),
                body: .json(.init(deadline: deadline?.iso))
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

    /// The signed-in user's id (`getMe`); nothing else of the answer is kept.
    public func currentUserID(in scope: DocumentScope) async throws -> UUID {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            switch try await client.getMe() {
            case let .ok(response):
                guard let id = UUID(uuidString: try response.body.json.id) else { throw ServerError.incompatible }
                return id
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }
}

private extension MyTasks {
    init(answer: Components.Schemas.MyTasksOut) throws(ServerError) {
        guard let today = CalendarDate(iso: answer.today) else { throw .incompatible }
        var items: [WorkspaceTask] = []
        for item in answer.items {
            items.append(try WorkspaceTask(task: item))
        }
        self.init(
            items: items, today: today, hasPerson: answer.hasPerson, truncated: answer.truncated,
            waitingLetters: answer.waitingLetters, split: answer.split
        )
    }
}
