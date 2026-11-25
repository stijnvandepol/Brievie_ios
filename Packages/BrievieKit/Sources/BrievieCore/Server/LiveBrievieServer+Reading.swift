import BrievieAPI
import Foundation
import OpenAPIRuntime

/// "Mijn post", "Ongelezen" and "Blijft liggen" (host PR #44). A server before that answers 404 without a Brievie
/// code (`http_404`, read as "not supported").
extension LiveBrievieServer {
    public func menuCounts(in scope: DocumentScope) async throws -> MenuCounts {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            switch try await client.getMenuCounts(path: .init(workspaceId: scope.workspaceID.apiString)) {
            case let .ok(response):
                let counts = try response.body.json
                return MenuCounts(
                    inbox: counts.inbox ?? 0, myPostUnread: counts.myPostUnread ?? 0, myTasks: counts.myTasks ?? 0,
                    myTasksOverdue: counts.myTasksOverdue ?? 0, lingering: counts.lingering ?? 0,
                    showsLingering: counts.showsLingering ?? false, hasPerson: counts.hasPerson ?? true
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

    public func markRead(_ id: UUID, in scope: DocumentScope) async throws {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.markDocumentRead(
                path: .init(workspaceId: scope.workspaceID.apiString, documentId: id.apiString)
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
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func markUnread(_ id: UUID, in scope: DocumentScope) async throws {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.markDocumentUnread(
                path: .init(workspaceId: scope.workspaceID.apiString, documentId: id.apiString)
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
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func markRead(_ ids: [UUID], in scope: DocumentScope) async throws -> Int {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.markDocumentsRead(
                path: .init(workspaceId: scope.workspaceID.apiString),
                body: .json(.init(documentIds: ids.map(\.apiString)))
            )
            switch output {
            case let .ok(response):
                return try response.body.json.marked
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

    public func lingeringLetters(in scope: DocumentScope) async throws -> LingeringLetters {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            switch try await client.listLingeringLetters(path: .init(workspaceId: scope.workspaceID.apiString)) {
            case let .ok(response):
                let answer = try response.body.json
                return LingeringLetters(
                    tooLongInInbox: try answer.tooLongInInbox.map(LingeringLetter.init(letter:)),
                    notOpened: try answer.notOpened.map(LingeringLetter.init(letter:)),
                    inboxDays: answer.inboxDays, unopenedDays: answer.unopenedDays
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

private extension LingeringLetter {
    init(letter: Components.Schemas.LingeringLetterOut) throws(ServerError) {
        try self.init(
            document: DocumentSummary(
                apiID: letter.id, clientID: letter.clientId, status: letter.status, pageCount: letter.pageCount,
                createdAt: letter.createdAt, sender: letter.sender, documentType: letter.documentType,
                letterDate: letter.letterDate, inboxState: letter.inboxState, addresseeIDs: letter.addresseeIds,
                labelIDs: letter.labelIds, openSuggestionCount: letter.openSuggestionCount,
                automatic: AutomaticMarks(
                    confirmedByAI: letter.confirmedByAi, labelIDs: letter.autoLabelIds,
                    addresseeIDs: letter.autoAddresseeIds
                ),
                proposedSender: letter.proposedSender, openDuplicateCount: letter.openDuplicateCount,
                unread: letter.unread
            ),
            days: letter.days ?? 0
        )
    }
}
