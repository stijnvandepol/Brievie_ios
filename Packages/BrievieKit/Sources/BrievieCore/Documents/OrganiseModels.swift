import Foundation

/// Someone post can be addressed to, within one workspace.
public struct Person: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let displayName: String
    /// Other spellings of the name the server recognises in a letter.
    public let nameVariants: [String]
    public let isArchived: Bool

    public init(id: UUID, displayName: String, nameVariants: [String], isArchived: Bool) {
        self.id = id
        self.displayName = displayName
        self.nameVariants = nameVariants
        self.isArchived = isArchived
    }
}

public struct DocumentLabel: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    /// The server's colour name; a screen shows a colour it does not know as grey.
    public let colorKey: String

    public init(id: UUID, name: String, colorKey: String) {
        self.id = id
        self.name = name
        self.colorKey = colorKey
    }
}

/// Where a document stands in the inbox. Raw values match the API; a done document with an addressee has
/// the empty state. A state this app does not know yet is `.unknown`.
public enum InboxState: String, Equatable, Sendable {
    case new
    case review
    case unassigned
    case sorted = ""
    case unknown

    public init(apiValue: String) {
        self = Self(rawValue: apiValue) ?? .unknown
    }
}

/// Raw values match the API. A suggestion with an action this app does not know is dropped while mapping.
public enum SuggestionAction: String, Equatable, Sendable {
    case addLabel = "add_label"
    case addAddressee = "add_addressee"
    case unknown
}

/// Where a suggestion came from. Raw values match the API.
public enum SuggestionOrigin: String, Equatable, Sendable {
    case rule
    case nameMatch = "name_match"
    case ai
    case unknown
}

/// An open proposal of the server to put a label or an addressee on a document.
public struct Suggestion: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let action: SuggestionAction
    /// The label id for `.addLabel`, the person id for `.addAddressee`.
    public let targetID: UUID
    public let origin: SuggestionOrigin
    /// The rule that made the suggestion; empty for other origins.
    public let ruleName: String
    /// The words in the letter the suggestion rests on; may be empty.
    public let quote: String
    public let confidence: Decimal
    /// Ticked in the review from the start (a name recognised with a strong sign).
    public let isPreselected: Bool

    public init(
        id: UUID, action: SuggestionAction, targetID: UUID, origin: SuggestionOrigin, ruleName: String,
        quote: String, confidence: Decimal, isPreselected: Bool
    ) {
        self.id = id
        self.action = action
        self.targetID = targetID
        self.origin = origin
        self.ruleName = ruleName
        self.quote = quote
        self.confidence = confidence
        self.isPreselected = isPreselected
    }
}

/// Which documents a list shows. `nil` means "no filter on this". Only `.new`, `.review` and `.unassigned` filter
/// on the inbox state: `.sorted` and `.unknown` are not filters and send no query (they list like `nil`).
public struct DocumentFilter: Equatable, Sendable {
    public var inboxState: InboxState?
    public var personID: UUID?

    public static let all = DocumentFilter()

    public init(inboxState: InboxState? = nil, personID: UUID? = nil) {
        self.inboxState = inboxState
        self.personID = personID
    }
}

/// How many letters of the whole workspace are in each inbox state; the lists show at most the newest 200.
public struct InboxCounts: Equatable, Sendable {
    public let new: Int
    public let review: Int
    public let unassigned: Int

    public init(new: Int, review: Int, unassigned: Int) {
        self.new = new
        self.review = review
        self.unassigned = unassigned
    }

    /// The count of one of the three inbox states; `nil` for a state that is not in the inbox.
    public func count(of state: InboxState) -> Int? {
        switch state {
        case .new: new
        case .review: review
        case .unassigned: unassigned
        case .sorted, .unknown: nil
        }
    }
}

/// A task of the workspace, with the letter it came from.
public struct WorkspaceTask: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let type: String
    public let description: String
    public let deadline: CalendarDate?
    public let isDone: Bool
    /// The letter the task belongs to; `nil` for a task without one.
    public let documentID: UUID?
    public let sender: String

    public init(
        id: UUID, type: String, description: String, deadline: CalendarDate?, isDone: Bool, documentID: UUID?,
        sender: String
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.deadline = deadline
        self.isDone = isDone
        self.documentID = documentID
        self.sender = sender
    }
}
