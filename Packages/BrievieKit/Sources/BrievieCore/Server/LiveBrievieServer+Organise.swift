import BrievieAPI
import Foundation
import OpenAPIRuntime

/// Persons, labels, addressees and suggestions (phase 1c).
extension LiveBrievieServer {
    public func persons(in scope: DocumentScope) async throws -> [Person] {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            switch try await client.listPersons(path: .init(workspaceId: scope.workspaceID.apiString)) {
            case let .ok(response):
                return try response.body.json.map(Person.init(person:))
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func createPerson(named name: String, in scope: DocumentScope) async throws -> Person {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.createPerson(
                path: .init(workspaceId: scope.workspaceID.apiString),
                body: .json(.init(displayName: name))
            )
            switch output {
            case let .created(response):
                return try Person(person: response.body.json)
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

    public func labels(in scope: DocumentScope) async throws -> [DocumentLabel] {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            switch try await client.listLabels(path: .init(workspaceId: scope.workspaceID.apiString)) {
            case let .ok(response):
                return try response.body.json.map(DocumentLabel.init(label:))
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func setAddressees(
        _ ids: [UUID], document: UUID, in scope: DocumentScope
    ) async throws -> DocumentDetail {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.setDocumentAddressees(
                path: .init(workspaceId: scope.workspaceID.apiString, documentId: document.apiString),
                body: .json(.init(personIds: ids.map(\.apiString)))
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

    public func setLabels(_ ids: [UUID], document: UUID, in scope: DocumentScope) async throws -> DocumentDetail {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.setDocumentLabels(
                path: .init(workspaceId: scope.workspaceID.apiString, documentId: document.apiString),
                body: .json(.init(labelIds: ids.map(\.apiString)))
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

    public func acceptSuggestion(
        _ id: UUID, document: UUID, in scope: DocumentScope
    ) async throws -> DocumentDetail {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.acceptSuggestion(path: .init(
                workspaceId: scope.workspaceID.apiString, documentId: document.apiString, suggestionId: id.apiString
            ))
            switch output {
            case let .ok(response):
                return try DocumentDetail(document: response.body.json)
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
            case let .forbidden(response):
                throw ServerError(status: 403, code: try? response.body.json.code)
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .conflict(response):
                throw ServerError(status: 409, code: try? response.body.json.code)
            case let .unprocessableContent(response):
                throw ServerError(status: 422, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func dismissSuggestion(
        _ id: UUID, document: UUID, in scope: DocumentScope
    ) async throws -> DocumentDetail {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.dismissSuggestion(path: .init(
                workspaceId: scope.workspaceID.apiString, documentId: document.apiString, suggestionId: id.apiString
            ))
            switch output {
            case let .ok(response):
                return try DocumentDetail(document: response.body.json)
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

private extension Person {
    init(person: Components.Schemas.PersonOut) throws(ServerError) {
        guard let id = UUID(uuidString: person.id) else { throw .incompatible }
        self.init(
            id: id, displayName: person.displayName, nameVariants: person.nameVariants, isArchived: person.archived
        )
    }
}

private extension DocumentLabel {
    init(label: Components.Schemas.LabelOut) throws(ServerError) {
        guard let id = UUID(uuidString: label.id) else { throw .incompatible }
        self.init(id: id, name: label.name, colorKey: label.color)
    }
}
