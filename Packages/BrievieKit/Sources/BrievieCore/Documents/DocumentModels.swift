import Foundation

/// Raw values match the API. API v1 is additive: a status this app does not know yet is `.unknown`.
public enum DocumentStatus: String, Sendable {
    case processing
    case needsReview = "needs_review"
    case done
    case failed
    case unknown
}

public struct DocumentSummary: Equatable, Sendable, Identifiable {
    public let id: UUID
    /// The id the uploading app chose: equal to the upload queue item's id.
    public let clientID: UUID
    public let status: DocumentStatus
    public let pageCount: Int
    public let createdAt: Date
    public let sender: String
    public let documentType: String
    public let letterDate: CalendarDate?

    public init(
        id: UUID, clientID: UUID, status: DocumentStatus, pageCount: Int, createdAt: Date, sender: String,
        documentType: String, letterDate: CalendarDate?
    ) {
        self.id = id
        self.clientID = clientID
        self.status = status
        self.pageCount = pageCount
        self.createdAt = createdAt
        self.sender = sender
        self.documentType = documentType
        self.letterDate = letterDate
    }
}

/// One value the server proposes for a document, with where it was read and how sure the AI is.
public struct Proposal: Equatable, Sendable {
    public let field: String
    /// 0 for values about the document; 1...n ties the values of one proposed action together.
    public let group: Int
    public let value: String
    /// The words in the letter the value was read from; empty for generated text.
    public let quote: String
    public let confidence: Decimal
    public let needsAttention: Bool
    public let provider: String
    public let model: String

    public init(
        field: String, group: Int, value: String, quote: String, confidence: Decimal, needsAttention: Bool,
        provider: String, model: String
    ) {
        self.field = field
        self.group = group
        self.value = value
        self.quote = quote
        self.confidence = confidence
        self.needsAttention = needsAttention
        self.provider = provider
        self.model = model
    }
}

public struct ConfirmedTask: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let type: String
    public let description: String
    public let deadline: CalendarDate?
    public let deadlineSource: String
    public let deadlineQuote: String

    public init(
        id: UUID, type: String, description: String, deadline: CalendarDate?, deadlineSource: String,
        deadlineQuote: String
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.deadline = deadline
        self.deadlineSource = deadlineSource
        self.deadlineQuote = deadlineQuote
    }
}

public struct DocumentDetail: Equatable, Sendable {
    public let summary: DocumentSummary
    /// Why processing failed; empty otherwise.
    public let failureCode: String
    public let summaryText: String
    public let summaryByAI: Bool
    /// The recognised text per page, in page order.
    public let pageTexts: [String]
    public let proposals: [Proposal]
    public let tasks: [ConfirmedTask]

    public init(
        summary: DocumentSummary, failureCode: String, summaryText: String, summaryByAI: Bool,
        pageTexts: [String], proposals: [Proposal], tasks: [ConfirmedTask]
    ) {
        self.summary = summary
        self.failureCode = failureCode
        self.summaryText = summaryText
        self.summaryByAI = summaryByAI
        self.pageTexts = pageTexts
        self.proposals = proposals
        self.tasks = tasks
    }
}

/// A task as the user is about to confirm it.
public struct TaskDraft: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var type: String
    public var description: String
    public var deadline: CalendarDate?
    /// `in_document` (then `deadlineQuote` holds the words from the letter) or `manual`.
    public var deadlineSource: String
    public var deadlineQuote: String
    public var needsAttention: Bool

    public init(
        id: UUID = UUID(), type: String, description: String, deadline: CalendarDate?, deadlineSource: String,
        deadlineQuote: String, needsAttention: Bool
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.deadline = deadline
        self.deadlineSource = deadlineSource
        self.deadlineQuote = deadlineQuote
        self.needsAttention = needsAttention
    }
}

/// What the user confirmed in the review. Nothing becomes a task without it.
public struct ConfirmedReview: Equatable, Sendable {
    public var sender: String
    public var documentType: String
    public var letterDate: CalendarDate?
    public var summary: String
    public var summaryByAI: Bool
    public var tasks: [TaskDraft]

    public init(
        sender: String, documentType: String, letterDate: CalendarDate?, summary: String, summaryByAI: Bool,
        tasks: [TaskDraft]
    ) {
        self.sender = sender
        self.documentType = documentType
        self.letterDate = letterDate
        self.summary = summary
        self.summaryByAI = summaryByAI
        self.tasks = tasks
    }
}

/// Where a document call goes: one server address of the pairing, and the workspace.
public struct DocumentScope: Sendable {
    public let url: URL
    public let trust: ServerTrust
    public let token: String
    public let workspaceID: UUID

    public init(url: URL, trust: ServerTrust, token: String, workspaceID: UUID) {
        self.url = url
        self.trust = trust
        self.token = token
        self.workspaceID = workspaceID
    }
}

/// The document calls the app makes to a Brievie server. Features talk to this seam, never to the
/// generated API types. (Uploading goes through the upload queue, not through here.)
public protocol DocumentServer: Sendable {
    /// The newest documents of the workspace.
    func documents(in scope: DocumentScope) async throws -> [DocumentSummary]
    func document(_ id: UUID, in scope: DocumentScope) async throws -> DocumentDetail
    /// The JPEG of one page (1-based index).
    func pageImage(document id: UUID, index: Int, in scope: DocumentScope) async throws -> Data
    func confirm(_ id: UUID, review: ConfirmedReview, in scope: DocumentScope) async throws -> DocumentDetail
    func retryProcessing(_ id: UUID, in scope: DocumentScope) async throws -> DocumentDetail
}
