import BrievieAPI
import Foundation
import OpenAPIRuntime

extension LiveBrievieServer: DocumentServer {
    /// A page is at most a few megabytes (2400 px JPEG); more than this is not one of ours.
    static let maxPageImageBytes = 20 * 1024 * 1024

    public func documents(in scope: DocumentScope, filter: DocumentFilter) async throws -> [DocumentSummary] {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.listDocuments(
                path: .init(workspaceId: scope.workspaceID.apiString),
                query: .init(inboxState: filter.inboxState?.queryValue, personId: filter.personID?.apiString)
            )
            switch output {
            case let .ok(response):
                return try response.body.json.map(DocumentSummary.init(summary:))
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

    /// The term goes in the body (a POST), so it never shows up in a URL or a proxy's access log.
    public func search(_ query: DocumentSearchQuery, in scope: DocumentScope) async throws -> DocumentSearchPage {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.searchDocuments(
                path: .init(workspaceId: scope.workspaceID.apiString),
                body: .json(.init(limit: DocumentSearchQuery.pageSize, offset: query.offset, q: query.text))
            )
            switch output {
            case let .ok(response):
                let page = try response.body.json
                return try DocumentSearchPage(
                    hits: page.items.map(DocumentSearchHit.init(hit:)), nextOffset: page.nextOffset,
                    isFuzzy: page.fuzzy ?? false, bsnRemoved: page.bsnRemoved ?? false
                )
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .unprocessableContent(response):
                throw ServerError(status: 422, code: try? response.body.json.code)
            case .tooManyRequests:
                throw ServerError.tooManyAttempts
            case let .badRequest(response):
                throw ServerError(status: 400, code: try? response.body.json.code)
            case let .forbidden(response):
                throw ServerError(status: 403, code: try? response.body.json.code)
            case .contentTooLarge:
                throw ServerError(status: 413, code: nil)
            case .unsupportedMediaType:
                throw ServerError(status: 415, code: nil)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func inboxCounts(in scope: DocumentScope) async throws -> InboxCounts {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            switch try await client.getInboxCounts(path: .init(workspaceId: scope.workspaceID.apiString)) {
            case let .ok(response):
                let counts = try response.body.json
                return InboxCounts(
                    new: counts.new, review: counts.review, unassigned: counts.unassigned,
                    duplicate: counts.duplicate ?? 0
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

    public func document(_ id: UUID, in scope: DocumentScope) async throws -> DocumentDetail {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.getDocument(
                path: .init(workspaceId: scope.workspaceID.apiString, documentId: id.apiString)
            )
            switch output {
            case let .ok(response):
                return try DocumentDetail(document: response.body.json)
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
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
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
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

    public func retryProcessing(_ id: UUID, in scope: DocumentScope) async throws -> DocumentDetail {
        try await withClient(scope.url, trust: scope.trust, token: scope.token) { client in
            let output = try await client.retryDocumentProcessing(
                path: .init(workspaceId: scope.workspaceID.apiString, documentId: id.apiString)
            )
            switch output {
            case let .accepted(response):
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

extension UUID {
    /// The API writes ids in lower case.
    var apiString: String { uuidString.lowercased() }
}

private extension InboxState {
    /// The `inbox_state` filter for this state; the server filters on the three inbox states only.
    var queryValue: String? {
        switch self {
        case .new, .review, .unassigned: rawValue
        case .sorted, .unknown: nil
        }
    }
}

/// Ids the API sends; one this app cannot read means the answer is not from a compatible server.
private func uuids(_ texts: [String]) throws(ServerError) -> [UUID] {
    var ids: [UUID] = []
    for text in texts {
        guard let id = UUID(uuidString: text) else { throw .incompatible }
        ids.append(id)
    }
    return ids
}

/// A confidence this app cannot read counts as "not sure at all".
private func apiDecimal(_ text: String) -> Decimal {
    Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0
}

private extension InboxState {
    /// A 1b server sends no inbox state: then it follows from the status.
    init(apiValue: String?, status: DocumentStatus) {
        if let apiValue {
            self.init(apiValue: apiValue)
            return
        }
        self = switch status {
        case .processing: .new
        case .needsReview, .failed: .review
        case .done: .sorted
        case .unknown: .unknown
        }
    }
}

private extension DocumentSearchHit {
    init(hit: Components.Schemas.DocumentSearchHitOut) throws(ServerError) {
        try self.init(
            document: DocumentSummary(
                apiID: hit.id, clientID: hit.clientId, status: hit.status, pageCount: hit.pageCount,
                createdAt: hit.createdAt, sender: hit.sender, documentType: hit.documentType,
                letterDate: hit.letterDate, inboxState: hit.inboxState, addresseeIDs: hit.addresseeIds,
                labelIDs: hit.labelIds, openSuggestionCount: hit.openSuggestionCount,
                automatic: AutomaticMarks(
                    confirmedByAI: hit.confirmedByAi, labelIDs: hit.autoLabelIds, addresseeIDs: hit.autoAddresseeIds
                ),
                proposedSender: hit.proposedSender, openDuplicateCount: hit.openDuplicateCount
            ),
            snippet: (hit.snippet ?? []).map { SnippetPart(text: $0.text, isHit: $0.hit) }
        )
    }
}

extension DocumentSummary {
    init(summary: Components.Schemas.DocumentSummaryOut) throws(ServerError) {
        try self.init(
            apiID: summary.id, clientID: summary.clientId, status: summary.status, pageCount: summary.pageCount,
            createdAt: summary.createdAt, sender: summary.sender, documentType: summary.documentType,
            letterDate: summary.letterDate, inboxState: summary.inboxState, addresseeIDs: summary.addresseeIds,
            labelIDs: summary.labelIds, openSuggestionCount: summary.openSuggestionCount,
            automatic: AutomaticMarks(
                confirmedByAI: summary.confirmedByAi, labelIDs: summary.autoLabelIds,
                addresseeIDs: summary.autoAddresseeIds
            ),
            proposedSender: summary.proposedSender, openDuplicateCount: summary.openDuplicateCount
        )
    }

    /// The one mapping of the fields a list entry and a detail share. The organise fields are optional in
    /// the contract: a 1b server leaves them out, which reads as none.
    init(
        apiID: String, clientID: String, status: String, pageCount: Int, createdAt: Date, sender: String,
        documentType: String, letterDate: String?, inboxState: String?, addresseeIDs: [String]?,
        labelIDs: [String]?, openSuggestionCount: Int?, automatic: AutomaticMarks, proposedSender: String?,
        openDuplicateCount: Int?
    ) throws(ServerError) {
        guard let id = UUID(uuidString: apiID), let clientID = UUID(uuidString: clientID) else {
            throw .incompatible
        }
        let status = DocumentStatus(rawValue: status) ?? .unknown
        self.init(
            id: id, clientID: clientID, status: status, pageCount: pageCount, createdAt: createdAt, sender: sender,
            documentType: documentType, letterDate: letterDate.flatMap(CalendarDate.init(iso:)),
            inboxState: InboxState(apiValue: inboxState, status: status),
            addresseeIDs: try uuids(addresseeIDs ?? []), labelIDs: try uuids(labelIDs ?? []),
            openSuggestionCount: openSuggestionCount ?? 0,
            confirmedByAI: automatic.confirmedByAI ?? false,
            autoLabelIDs: try uuids(automatic.labelIDs ?? []),
            autoAddresseeIDs: try uuids(automatic.addresseeIDs ?? []),
            proposedSender: proposedSender ?? "", openDuplicateCount: openDuplicateCount ?? 0
        )
    }
}

/// What the AI did by itself; a server before the autopilot leaves all three out, which reads as nothing.
struct AutomaticMarks {
    let confirmedByAI: Bool?
    let labelIDs: [String]?
    let addresseeIDs: [String]?
}

private extension Suggestion {
    /// `nil` for a suggestion this app cannot show: an unknown action, or no id for its target.
    init?(suggestion: Components.Schemas.SuggestionOut) {
        let action = SuggestionAction(rawValue: suggestion.action) ?? .unknown
        let target: String? = switch action {
        case .addLabel: suggestion.labelId
        case .addAddressee: suggestion.personId
        case .unknown: nil
        }
        guard let id = UUID(uuidString: suggestion.id), let targetID = target.flatMap(UUID.init(uuidString:)) else {
            return nil
        }
        self.init(
            id: id, action: action, targetID: targetID,
            origin: SuggestionOrigin(rawValue: suggestion.origin) ?? .unknown, ruleName: suggestion.ruleName,
            quote: suggestion.quote, confidence: apiDecimal(suggestion.confidence),
            isPreselected: suggestion.preselected
        )
    }
}

extension DocumentDetail {
    init(document: Components.Schemas.DocumentOut) throws(ServerError) {
        let summary = try DocumentSummary(
            apiID: document.id, clientID: document.clientId, status: document.status, pageCount: document.pageCount,
            createdAt: document.createdAt, sender: document.sender, documentType: document.documentType,
            letterDate: document.letterDate, inboxState: document.inboxState, addresseeIDs: document.addresseeIds,
            labelIDs: document.labelIds, openSuggestionCount: document.openSuggestionCount,
            automatic: AutomaticMarks(
                confirmedByAI: document.confirmedByAi, labelIDs: document.autoLabelIds,
                addresseeIDs: document.autoAddresseeIds
            ),
            proposedSender: document.proposedSender, openDuplicateCount: document.openDuplicateCount
        )
        var tasks: [ConfirmedTask] = []
        for task in document.tasks {
            guard let taskID = UUID(uuidString: task.id) else { throw .incompatible }
            var assignedToID: UUID?
            if let text = task.assignedToId {
                guard let id = UUID(uuidString: text) else { throw .incompatible }
                assignedToID = id
            }
            tasks.append(ConfirmedTask(
                id: taskID, type: task._type, description: task.description,
                deadline: task.deadline.flatMap(CalendarDate.init(iso:)), deadlineSource: task.deadlineSource,
                deadlineQuote: task.deadlineQuote, isDone: task.status == "done",
                createdByAI: task.createdByAi ?? false, amount: task.amount.flatMap(TaskAmount.parse(api:)),
                termQuote: task.termQuote ?? "", assignedToID: assignedToID,
                assignedToName: task.assignedToName ?? ""
            ))
        }
        self.init(
            summary: summary,
            failureCode: document.failureCode,
            summaryText: document.summary,
            summaryByAI: document.summaryByAi,
            pageTexts: document.pages.sorted { $0.index < $1.index }.map(\.ocrText),
            proposals: document.proposals.map { proposal in
                Proposal(
                    field: proposal.field, group: proposal.group, value: proposal.value, quote: proposal.quote,
                    confidence: apiDecimal(proposal.confidence),
                    needsAttention: proposal.needsAttention, provider: proposal.provider, model: proposal.model
                )
            },
            tasks: tasks,
            suggestions: (document.suggestions ?? []).compactMap(Suggestion.init(suggestion:))
        )
    }
}

private extension Components.Schemas.ConfirmIn {
    init(review: ConfirmedReview) {
        self.init(
            // Always sent, also when empty: with `setsOrganisation` false the server leaves both as they are.
            addresseeIds: review.addresseeIDs.map(\.apiString),
            documentType: review.documentType,
            labelIds: review.labelIDs.map(\.apiString),
            // A nil date is left out of the JSON; the host reads a missing field as "none".
            letterDate: review.letterDate?.iso,
            sender: review.sender,
            setsOrganisation: review.setsOrganisation,
            summary: review.summary,
            summaryByAi: review.summaryByAI,
            tasks: review.tasks.map { task in
                .init(
                    // Only the API's own form goes out; anything else is "unknown" (the review blocks it first).
                    amount: TaskAmount.parse(api: task.amount).map(TaskAmount.api) ?? "",
                    deadline: task.deadline?.iso, deadlineQuote: task.deadlineQuote,
                    deadlineSource: task.deadlineSource, description: task.description, _type: task.type
                )
            }
        )
    }
}
