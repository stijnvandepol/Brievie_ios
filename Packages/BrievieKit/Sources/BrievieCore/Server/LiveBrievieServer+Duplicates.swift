import BrievieAPI
import Foundation
import OpenAPIRuntime

/// Letters that look scanned twice: list and read the open pairs, merge or dismiss one (host PR #34).
extension LiveBrievieServer {
    public func duplicates(in scope: DocumentScope) async throws -> [DuplicatePair] {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            switch try await client.listDuplicates(path: .init(workspaceId: scope.workspaceID.apiString)) {
            case let .ok(response):
                return try response.body.json.map(DuplicatePair.init(pair:))
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func duplicate(_ id: UUID, in scope: DocumentScope) async throws -> DuplicatePair {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.getDuplicate(
                path: .init(workspaceId: scope.workspaceID.apiString, duplicateId: id.apiString)
            )
            switch output {
            case let .ok(response):
                return try DuplicatePair(pair: response.body.json)
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func mergeDuplicate(
        _ id: UUID, keep: UUID, completeTwinTasks: Bool, in scope: DocumentScope
    ) async throws -> DocumentDetail {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.mergeDuplicate(
                path: .init(workspaceId: scope.workspaceID.apiString, duplicateId: id.apiString),
                body: .json(.init(completeTwinTasks: completeTwinTasks, keepDocumentId: keep.apiString))
            )
            switch output {
            case let .ok(response):
                return try DocumentDetail(document: response.body.json)
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
            case let .badRequest(response):
                throw ServerError(status: 400, code: try? response.body.json.code)
            case let .forbidden(response):
                throw ServerError(status: 403, code: try? response.body.json.code)
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .conflict(response):
                throw ServerError(status: 409, code: try? response.body.json.code)
            case .contentTooLarge:
                throw ServerError(status: 413, code: nil)
            case .unsupportedMediaType:
                throw ServerError(status: 415, code: nil)
            case let .unprocessableContent(response):
                throw ServerError(status: 422, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func dismissDuplicate(_ id: UUID, in scope: DocumentScope) async throws {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.dismissDuplicate(
                path: .init(workspaceId: scope.workspaceID.apiString, duplicateId: id.apiString)
            )
            switch output {
            case .noContent:
                return
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
            case let .forbidden(response):
                throw ServerError(status: 403, code: try? response.body.json.code)
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .conflict(response):
                throw ServerError(status: 409, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }
}

private extension DuplicatePair {
    init(pair: Components.Schemas.DuplicateOut) throws(ServerError) {
        guard let id = UUID(uuidString: pair.id), let keepID = UUID(uuidString: pair.suggestedKeepId) else {
            throw .incompatible
        }
        var twins: [TaskTwin] = []
        for twin in pair.taskTwins ?? [] {
            guard let done = UUID(uuidString: twin.doneDocumentId), let open = UUID(uuidString: twin.openDocumentId)
            else { throw .incompatible }
            twins.append(TaskTwin(
                doneDocumentID: done, openDocumentID: open, type: twin._type, description: twin.description
            ))
        }
        try self.init(
            id: id, createdAt: pair.createdAt, first: DocumentSummary(summary: pair.first),
            second: DocumentSummary(summary: pair.second), suggestedKeepID: keepID, similarity: pair.textSimilarity,
            same: (pair.same ?? []).map(DuplicateField.init(apiValue:)),
            differences: (pair.differences ?? []).map { difference in
                DuplicateDifference(
                    field: DuplicateField(apiValue: difference.field), first: difference.first,
                    second: difference.second, isUncertain: difference.uncertain ?? false
                )
            },
            taskTwins: twins, canMerge: pair.canMerge ?? true, blockedReason: pair.blockedReason ?? ""
        )
    }
}
