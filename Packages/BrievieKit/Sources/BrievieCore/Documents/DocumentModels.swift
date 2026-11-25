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
    public let inboxState: InboxState
    /// The persons the letter is addressed to.
    public let addresseeIDs: [UUID]
    public let labelIDs: [UUID]
    public let openSuggestionCount: Int
    /// The AI confirmed the letter itself (the workspace's autopilot); nobody checked it.
    public let confirmedByAI: Bool
    /// Labels and addressees the AI or a rule put on the letter by itself and nobody confirmed yet.
    public let autoLabelIDs: [UUID]
    public let autoAddresseeIDs: [UUID]
    /// The sender the AI proposed for a letter waiting for review; empty when the server does not list it (before
    /// host PR #25) or has none. A proposal, never the confirmed `sender`.
    public let proposedSender: String
    /// How many open duplicate pairs this letter is in (0 from a server before host PR #34).
    public let openDuplicateCount: Int
    /// "Ongelezen": the member has not opened this letter yet (false from a server before host PR #44).
    public var isUnread: Bool

    /// "Dubbel?": the letter is in a pair that still waits for a choice.
    public var isPossibleDuplicate: Bool { openDuplicateCount > 0 }

    /// "Automatisch door AI", as the web's lists say: confirmed by the AI, or with a label or name it put on.
    public var isAutomatic: Bool { confirmedByAI || !autoLabelIDs.isEmpty || !autoAddresseeIDs.isEmpty }

    public init(
        id: UUID, clientID: UUID, status: DocumentStatus, pageCount: Int, createdAt: Date, sender: String,
        documentType: String, letterDate: CalendarDate?, inboxState: InboxState = .sorted,
        addresseeIDs: [UUID] = [], labelIDs: [UUID] = [], openSuggestionCount: Int = 0,
        confirmedByAI: Bool = false, autoLabelIDs: [UUID] = [], autoAddresseeIDs: [UUID] = [],
        proposedSender: String = "", openDuplicateCount: Int = 0, isUnread: Bool = false
    ) {
        self.id = id
        self.clientID = clientID
        self.status = status
        self.pageCount = pageCount
        self.createdAt = createdAt
        self.sender = sender
        self.documentType = documentType
        self.letterDate = letterDate
        self.inboxState = inboxState
        self.addresseeIDs = addresseeIDs
        self.labelIDs = labelIDs
        self.openSuggestionCount = openSuggestionCount
        self.confirmedByAI = confirmedByAI
        self.autoLabelIDs = autoLabelIDs
        self.autoAddresseeIDs = autoAddresseeIDs
        self.proposedSender = proposedSender
        self.openDuplicateCount = openDuplicateCount
        self.isUnread = isUnread
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
    /// Ticked off (`status` is `done`).
    public var isDone: Bool
    /// The AI made this task when it confirmed the letter by itself.
    public let createdByAI: Bool
    /// The amount of a payment; `nil` when unknown (or from a server before "Mijn taken").
    public let amount: Decimal?
    /// The term the letter names without a date ("binnen zes weken").
    public let termQuote: String
    /// Who does the task; `nil` and empty when nobody has it yet.
    public var assignedToID: UUID?
    public var assignedToName: String
    /// What the server lets this member do with the task; `nil` from a server before host PR #44.
    public var permissions: TaskPermissions?

    public init(
        id: UUID, type: String, description: String, deadline: CalendarDate?, deadlineSource: String,
        deadlineQuote: String, isDone: Bool = false, createdByAI: Bool = false, amount: Decimal? = nil,
        termQuote: String = "", assignedToID: UUID? = nil, assignedToName: String = "",
        permissions: TaskPermissions? = nil
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.deadline = deadline
        self.deadlineSource = deadlineSource
        self.deadlineQuote = deadlineQuote
        self.isDone = isDone
        self.createdByAI = createdByAI
        self.amount = amount
        self.termQuote = termQuote
        self.assignedToID = assignedToID
        self.assignedToName = assignedToName
        self.permissions = permissions
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
    /// The open suggestions for addressees and labels this app knows how to show.
    public let suggestions: [Suggestion]

    public init(
        summary: DocumentSummary, failureCode: String, summaryText: String, summaryByAI: Bool,
        pageTexts: [String], proposals: [Proposal], tasks: [ConfirmedTask], suggestions: [Suggestion] = []
    ) {
        self.summary = summary
        self.failureCode = failureCode
        self.summaryText = summaryText
        self.summaryByAI = summaryByAI
        self.pageTexts = pageTexts
        self.proposals = proposals
        self.tasks = tasks
        self.suggestions = suggestions
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
    /// The amount of a payment: as typed in the review (the user's notation), the API's decimal string ("1234.56")
    /// once confirmed; empty when unknown.
    public var amount: String

    public init(
        id: UUID = UUID(), type: String, description: String, deadline: CalendarDate?, deadlineSource: String,
        deadlineQuote: String, needsAttention: Bool, amount: String = ""
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.deadline = deadline
        self.deadlineSource = deadlineSource
        self.deadlineQuote = deadlineQuote
        self.needsAttention = needsAttention
        self.amount = amount
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
    public var addresseeIDs: [UUID]
    public var labelIDs: [UUID]
    /// Whether the server sets the addressees and labels to the two lists. False leaves them as they are
    /// (and is what a review without the organise lists sends).
    public var setsOrganisation: Bool

    public init(
        sender: String, documentType: String, letterDate: CalendarDate?, summary: String, summaryByAI: Bool,
        tasks: [TaskDraft], addresseeIDs: [UUID] = [], labelIDs: [UUID] = [], setsOrganisation: Bool = false
    ) {
        self.sender = sender
        self.documentType = documentType
        self.letterDate = letterDate
        self.summary = summary
        self.summaryByAI = summaryByAI
        self.tasks = tasks
        self.addresseeIDs = addresseeIDs
        self.labelIDs = labelIDs
        self.setsOrganisation = setsOrganisation
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
    /// The newest documents of the workspace that match `filter`.
    func documents(in scope: DocumentScope, filter: DocumentFilter) async throws -> [DocumentSummary]
    /// The number of letters per inbox state over the whole workspace (a 1b server does not have this).
    func inboxCounts(in scope: DocumentScope) async throws -> InboxCounts
    func document(_ id: UUID, in scope: DocumentScope) async throws -> DocumentDetail
    /// The JPEG of one page (1-based index).
    func pageImage(document id: UUID, index: Int, in scope: DocumentScope) async throws -> Data
    func confirm(_ id: UUID, review: ConfirmedReview, in scope: DocumentScope) async throws -> DocumentDetail
    func retryProcessing(_ id: UUID, in scope: DocumentScope) async throws -> DocumentDetail
    func persons(in scope: DocumentScope) async throws -> [Person]
    func createPerson(named name: String, in scope: DocumentScope) async throws -> Person
    func labels(in scope: DocumentScope) async throws -> [DocumentLabel]
    /// Replaces the addressees of a document with exactly `ids`.
    func setAddressees(_ ids: [UUID], document: UUID, in scope: DocumentScope) async throws -> DocumentDetail
    /// Replaces the labels of a document with exactly `ids`.
    func setLabels(_ ids: [UUID], document: UUID, in scope: DocumentScope) async throws -> DocumentDetail
    func acceptSuggestion(_ id: UUID, document: UUID, in scope: DocumentScope) async throws -> DocumentDetail
    func dismissSuggestion(_ id: UUID, document: UUID, in scope: DocumentScope) async throws -> DocumentDetail
    /// The open tasks of the workspace, by deadline (undated last).
    func openTasks(in scope: DocumentScope) async throws -> [WorkspaceTask]
    func completeTask(_ id: UUID, in scope: DocumentScope) async throws -> WorkspaceTask
    func reopenTask(_ id: UUID, in scope: DocumentScope) async throws -> WorkspaceTask
    /// One page of a search in the letters of the workspace (a server before host PR #27 answers 404).
    func search(_ query: DocumentSearchQuery, in scope: DocumentScope) async throws -> DocumentSearchPage
    /// Puts a letter in the trash (a server before host PR #32 answers 404).
    func trash(_ id: UUID, in scope: DocumentScope) async throws -> TrashedDocument
    /// Takes a letter out of the trash; the answer is the letter as it is now.
    func restore(_ id: UUID, in scope: DocumentScope) async throws -> DocumentDetail
    func trashList(in scope: DocumentScope) async throws -> TrashList
    /// The open duplicate pairs of the workspace (a server before host PR #34 answers 404).
    func duplicates(in scope: DocumentScope) async throws -> [DuplicatePair]
    func duplicate(_ id: UUID, in scope: DocumentScope) async throws -> DuplicatePair
    /// Keeps `keep` and puts the pair's other letter in the trash; the answer is the kept letter.
    func mergeDuplicate(
        _ id: UUID, keep: UUID, completeTwinTasks: Bool, in scope: DocumentScope
    ) async throws -> DocumentDetail
    /// "Het zijn twee brieven": the pair is not asked again.
    func dismissDuplicate(_ id: UUID, in scope: DocumentScope) async throws
    /// "Mijn taken": one part of the member's tasks (a server before host PR #36 answers 404).
    func myTasks(part: MyTasksPart, status: MyTasksStatus, in scope: DocumentScope) async throws -> MyTasks
    func myTaskCounts(in scope: DocumentScope) async throws -> MyTaskCounts
    /// Gives the task to `user`; `nil` releases it.
    func assignTask(_ id: UUID, to user: UUID?, in scope: DocumentScope) async throws -> WorkspaceTask
    /// The members a task can be handed to: those who may read its letter.
    func taskAssignees(_ id: UUID, in scope: DocumentScope) async throws -> [TaskAssignee]
    /// Sets (or with `nil` removes) the deadline the user read in the letter.
    func setTaskDeadline(_ id: UUID, to deadline: CalendarDate?, in scope: DocumentScope) async throws -> WorkspaceTask
    /// The signed-in user's id, for "Ik doe dit".
    func currentUserID(in scope: DocumentScope) async throws -> UUID
    /// The numbers of the menu (host PR #44; an older server answers 404).
    func menuCounts(in scope: DocumentScope) async throws -> MenuCounts
    /// The member opened the letter: it is no longer "Ongelezen" for them.
    func markRead(_ id: UUID, in scope: DocumentScope) async throws
    func markUnread(_ id: UUID, in scope: DocumentScope) async throws
    /// "Alles gelezen": at most 200 letters; the answer is how many the server marked.
    func markRead(_ ids: [UUID], in scope: DocumentScope) async throws -> Int
    /// "Blijft liggen" (organisations, for sorters and admins; empty otherwise).
    func lingeringLetters(in scope: DocumentScope) async throws -> LingeringLetters
}

public extension DocumentServer {
    /// For servers that predate search (the test servers): the 404 of a server without the endpoint.
    func search(_ query: DocumentSearchQuery, in scope: DocumentScope) async throws -> DocumentSearchPage {
        throw ServerError.other("http_404")
    }

    /// For servers that predate the trash: the 404 of a server without the endpoint.
    func trash(_ id: UUID, in scope: DocumentScope) async throws -> TrashedDocument {
        throw ServerError.other("http_404")
    }

    func restore(_ id: UUID, in scope: DocumentScope) async throws -> DocumentDetail {
        throw ServerError.other("http_404")
    }

    func trashList(in scope: DocumentScope) async throws -> TrashList {
        throw ServerError.other("http_404")
    }

    /// For servers that predate duplicate pairs: the 404 of a server without the endpoint.
    func duplicates(in scope: DocumentScope) async throws -> [DuplicatePair] {
        throw ServerError.other("http_404")
    }

    func duplicate(_ id: UUID, in scope: DocumentScope) async throws -> DuplicatePair {
        throw ServerError.other("http_404")
    }

    func mergeDuplicate(
        _ id: UUID, keep: UUID, completeTwinTasks: Bool, in scope: DocumentScope
    ) async throws -> DocumentDetail {
        throw ServerError.other("http_404")
    }

    func dismissDuplicate(_ id: UUID, in scope: DocumentScope) async throws {
        throw ServerError.other("http_404")
    }

    /// For servers that predate "Mijn taken": the 404 of a server without the endpoint.
    func myTasks(part: MyTasksPart, status: MyTasksStatus, in scope: DocumentScope) async throws -> MyTasks {
        throw ServerError.other("http_404")
    }

    func myTaskCounts(in scope: DocumentScope) async throws -> MyTaskCounts {
        throw ServerError.other("http_404")
    }

    func assignTask(_ id: UUID, to user: UUID?, in scope: DocumentScope) async throws -> WorkspaceTask {
        throw ServerError.other("http_404")
    }

    func taskAssignees(_ id: UUID, in scope: DocumentScope) async throws -> [TaskAssignee] {
        throw ServerError.other("http_404")
    }

    func setTaskDeadline(
        _ id: UUID, to deadline: CalendarDate?, in scope: DocumentScope
    ) async throws -> WorkspaceTask {
        throw ServerError.other("http_404")
    }

    func currentUserID(in scope: DocumentScope) async throws -> UUID {
        throw ServerError.other("http_404")
    }

    /// For servers that predate "Mijn post" and "Ongelezen": the 404 of a server without the endpoint.
    func menuCounts(in scope: DocumentScope) async throws -> MenuCounts {
        throw ServerError.other("http_404")
    }

    func markRead(_ id: UUID, in scope: DocumentScope) async throws {
        throw ServerError.other("http_404")
    }

    func markUnread(_ id: UUID, in scope: DocumentScope) async throws {
        throw ServerError.other("http_404")
    }

    func markRead(_ ids: [UUID], in scope: DocumentScope) async throws -> Int {
        throw ServerError.other("http_404")
    }

    func lingeringLetters(in scope: DocumentScope) async throws -> LingeringLetters {
        throw ServerError.other("http_404")
    }

    /// The newest documents of the workspace, unfiltered.
    func documents(in scope: DocumentScope) async throws -> [DocumentSummary] {
        try await documents(in: scope, filter: .all)
    }
}
