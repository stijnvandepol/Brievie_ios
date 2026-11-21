import Foundation

/// A fact the server compares between two letters of a pair. Raw values match the API; a field this app does not
/// know yet is `.unknown`.
public enum DuplicateField: String, Equatable, Sendable {
    case sender
    case letterDate = "letter_date"
    case documentType = "document_type"
    case amount
    case invoiceNumber = "invoice_number"
    case paymentReference = "payment_reference"
    case pageCount = "page_count"
    case unknown

    public init(apiValue: String) {
        self = Self(rawValue: apiValue) ?? .unknown
    }
}

/// One fact that differs between the two letters, as the server reads it (dates ISO, amounts decimal text).
public struct DuplicateDifference: Equatable, Sendable {
    public let field: DuplicateField
    public let first: String
    public let second: String
    /// The server could not read one of the values well: it may not differ at all.
    public let isUncertain: Bool

    public init(field: DuplicateField, first: String, second: String, isUncertain: Bool) {
        self.field = field
        self.first = first
        self.second = second
        self.isUncertain = isUncertain
    }
}

/// A task that exists on both letters: done on one, still open on the other.
public struct TaskTwin: Equatable, Sendable {
    public let doneDocumentID: UUID
    public let openDocumentID: UUID
    public let type: String
    public let description: String

    public init(doneDocumentID: UUID, openDocumentID: UUID, type: String, description: String) {
        self.doneDocumentID = doneDocumentID
        self.openDocumentID = openDocumentID
        self.type = type
        self.description = description
    }
}

/// Two letters that look scanned twice, still open (the server lists open pairs only).
public struct DuplicatePair: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let first: DocumentSummary
    public let second: DocumentSummary
    /// The letter the server suggests to keep.
    public let suggestedKeepID: UUID
    /// How alike the texts are, 0...100.
    public let similarity: Int
    /// The facts that are the same; a field this app does not know is left out.
    public let same: [DuplicateField]
    /// The facts that differ; a field this app does not know is left out.
    public let differences: [DuplicateDifference]
    public let taskTwins: [TaskTwin]
    /// False when the server would refuse a merge (the letters are not visible to the same people).
    public let canMerge: Bool
    /// Why the pair cannot merge ("visibility_differs"), or empty.
    public let blockedReason: String

    public init(
        id: UUID, createdAt: Date, first: DocumentSummary, second: DocumentSummary, suggestedKeepID: UUID,
        similarity: Int, same: [DuplicateField] = [], differences: [DuplicateDifference] = [],
        taskTwins: [TaskTwin] = [], canMerge: Bool = true, blockedReason: String = ""
    ) {
        self.id = id
        self.createdAt = createdAt
        self.first = first
        self.second = second
        self.suggestedKeepID = suggestedKeepID
        self.similarity = min(max(similarity, 0), 100)
        self.same = same.filter { $0 != .unknown }
        self.differences = differences.filter { $0.field != .unknown }
        self.taskTwins = taskTwins
        self.canMerge = canMerge
        self.blockedReason = blockedReason
    }
}
