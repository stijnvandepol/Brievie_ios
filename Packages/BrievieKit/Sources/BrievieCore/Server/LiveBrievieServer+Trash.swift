import BrievieAPI
import Foundation
import OpenAPIRuntime

/// The trash of a workspace: trash a letter, restore it, list the trash (host PR #32). Deleting for good and
/// emptying the trash are web-session only and not generated.
extension LiveBrievieServer {
    public func trash(_ id: UUID, in scope: DocumentScope) async throws -> TrashedDocument {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.trashDocument(
                path: .init(workspaceId: scope.workspaceID.apiString, documentId: id.apiString)
            )
            switch output {
            case let .ok(response):
                return try TrashedDocument(trashed: response.body.json)
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

    public func restore(_ id: UUID, in scope: DocumentScope) async throws -> DocumentDetail {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.restoreDocument(
                path: .init(workspaceId: scope.workspaceID.apiString, documentId: id.apiString)
            )
            switch output {
            case let .ok(response):
                return try DocumentDetail(document: response.body.json)
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

    public func trashList(in scope: DocumentScope) async throws -> TrashList {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            switch try await client.listTrash(path: .init(workspaceId: scope.workspaceID.apiString)) {
            case let .ok(response):
                let list = try response.body.json
                return try TrashList(
                    items: (list.items ?? []).map(TrashedDocument.init(trashed:)),
                    retentionDays: list.retentionDays ?? 30, total: list.total ?? 0
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
}

private extension TrashedDocument {
    init(trashed: Components.Schemas.TrashedDocumentOut) throws(ServerError) {
        try self.init(
            summary: DocumentSummary(
                apiID: trashed.id, clientID: trashed.clientId, status: trashed.status, pageCount: trashed.pageCount,
                createdAt: trashed.createdAt, sender: trashed.sender, documentType: trashed.documentType,
                letterDate: trashed.letterDate, inboxState: trashed.inboxState, addresseeIDs: trashed.addresseeIds,
                labelIDs: trashed.labelIds, openSuggestionCount: trashed.openSuggestionCount,
                automatic: AutomaticMarks(
                    confirmedByAI: trashed.confirmedByAi, labelIDs: trashed.autoLabelIds,
                    addresseeIDs: trashed.autoAddresseeIds
                ),
                proposedSender: trashed.proposedSender
            ),
            trashedAt: trashed.trashedAt, trashedByName: trashed.trashedByName ?? "", purgeAfter: trashed.purgeAfter
        )
    }
}
