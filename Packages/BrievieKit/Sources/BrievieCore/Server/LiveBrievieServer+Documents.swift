import BrievieAPI
import Foundation
import OpenAPIRuntime

extension LiveBrievieServer: DocumentServer {
    /// A page is at most a few megabytes (2400 px JPEG); more than this is not one of ours.
    static let maxPageImageBytes = 20 * 1024 * 1024

    public func documents(in scope: DocumentScope) async throws -> [DocumentSummary] {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.listDocuments(path: .init(workspaceId: scope.workspaceID.apiString))
            switch output {
            case let .ok(response):
                return try response.body.json.map(DocumentSummary.init(summary:))
            case .unauthorized:
                throw ServerError.unauthorized
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func document(_ id: UUID, in scope: DocumentScope) async throws -> DocumentDetail {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.getDocument(
                path: .init(workspaceId: scope.workspaceID.apiString, documentId: id.apiString)
            )
            switch output {
            case let .ok(response):
                return try DocumentDetail(document: response.body.json)
            case .unauthorized:
                throw ServerError.unauthorized
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func pageImage(document id: UUID, index: Int, in scope: DocumentScope) async throws -> Data {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.getDocumentPage(
                path: .init(workspaceId: scope.workspaceID.apiString, documentId: id.apiString, index: index)
            )
            switch output {
            case let .ok(response):
                var data = Data()
                for try await chunk in try response.body.jpeg {
                    data.append(contentsOf: chunk)
                    guard data.count <= Self.maxPageImageBytes else { throw ServerError.incompatible }
                }
                return data
            case .unauthorized:
                throw ServerError.unauthorized
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func confirm(
        _ id: UUID, review: ConfirmedReview, in scope: DocumentScope
    ) async throws -> DocumentDetail {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.confirmDocument(
                path: .init(workspaceId: scope.workspaceID.apiString, documentId: id.apiString),
                body: .json(.init(review: review))
            )
            switch output {
            case let .ok(response):
                return try DocumentDetail(document: response.body.json)
            case .unauthorized:
                throw ServerError.unauthorized
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

    public func retryProcessing(_ id: UUID, in scope: DocumentScope) async throws -> DocumentDetail {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.retryDocumentProcessing(
                path: .init(workspaceId: scope.workspaceID.apiString, documentId: id.apiString)
            )
            switch output {
            case let .accepted(response):
                return try DocumentDetail(document: response.body.json)
            case .unauthorized:
                throw ServerError.unauthorized
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

private extension UUID {
    /// The API writes ids in lower case.
    var apiString: String { uuidString.lowercased() }
}

private extension DocumentSummary {
    init(summary: Components.Schemas.DocumentSummaryOut) throws(ServerError) {
        guard let id = UUID(uuidString: summary.id), let clientID = UUID(uuidString: summary.clientId) else {
            throw .incompatible
        }
        self.init(
            id: id, clientID: clientID, status: DocumentStatus(rawValue: summary.status) ?? .unknown,
            pageCount: summary.pageCount, createdAt: summary.createdAt, sender: summary.sender,
            documentType: summary.documentType, letterDate: summary.letterDate.flatMap(CalendarDate.init(iso:))
        )
    }
}

private extension DocumentDetail {
    init(document: Components.Schemas.DocumentOut) throws(ServerError) {
        guard let id = UUID(uuidString: document.id), let clientID = UUID(uuidString: document.clientId) else {
            throw .incompatible
        }
        var tasks: [ConfirmedTask] = []
        for task in document.tasks {
            guard let taskID = UUID(uuidString: task.id) else { throw .incompatible }
            tasks.append(ConfirmedTask(
                id: taskID, type: task._type, description: task.description,
                deadline: task.deadline.flatMap(CalendarDate.init(iso:)), deadlineSource: task.deadlineSource,
                deadlineQuote: task.deadlineQuote
            ))
        }
        self.init(
            summary: DocumentSummary(
                id: id, clientID: clientID, status: DocumentStatus(rawValue: document.status) ?? .unknown,
                pageCount: document.pageCount, createdAt: document.createdAt, sender: document.sender,
                documentType: document.documentType,
                letterDate: document.letterDate.flatMap(CalendarDate.init(iso:))
            ),
            failureCode: document.failureCode,
            summaryText: document.summary,
            summaryByAI: document.summaryByAi,
            pageTexts: document.pages.sorted { $0.index < $1.index }.map(\.ocrText),
            proposals: document.proposals.map { proposal in
                Proposal(
                    field: proposal.field, group: proposal.group, value: proposal.value, quote: proposal.quote,
                    // A confidence this app cannot read counts as "not sure at all".
                    confidence: Decimal(string: proposal.confidence, locale: Locale(identifier: "en_US_POSIX")) ?? 0,
                    needsAttention: proposal.needsAttention, provider: proposal.provider, model: proposal.model
                )
            },
            tasks: tasks
        )
    }
}

private extension Components.Schemas.ConfirmIn {
    init(review: ConfirmedReview) {
        self.init(
            documentType: review.documentType,
            // A nil date is left out of the JSON; the host reads a missing field as "none".
            letterDate: review.letterDate?.iso,
            sender: review.sender,
            summary: review.summary,
            summaryByAi: review.summaryByAI,
            tasks: review.tasks.map { task in
                .init(
                    deadline: task.deadline?.iso, deadlineQuote: task.deadlineQuote,
                    deadlineSource: task.deadlineSource, description: task.description, _type: task.type
                )
            }
        )
    }
}
