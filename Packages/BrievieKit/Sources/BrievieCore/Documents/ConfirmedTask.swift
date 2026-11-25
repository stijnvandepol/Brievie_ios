import Foundation

/// A task of a confirmed letter, as the letter shows it.
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
    /// "Wacht op reactie" until this day (host PR #50); everyone who sees the letter sees it.
    public var waitingUntil: CalendarDate?
    /// The waiting date has come: "Wachten voorbij".
    public var waitOver: Bool
    /// "Uitgesteld tot", for this member only.
    public var snoozedUntil: CalendarDate?

    public init(
        id: UUID, type: String, description: String, deadline: CalendarDate?, deadlineSource: String,
        deadlineQuote: String, isDone: Bool = false, createdByAI: Bool = false, amount: Decimal? = nil,
        termQuote: String = "", assignedToID: UUID? = nil, assignedToName: String = "",
        permissions: TaskPermissions? = nil, waitingUntil: CalendarDate? = nil, waitOver: Bool = false,
        snoozedUntil: CalendarDate? = nil
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
        self.waitingUntil = waitingUntil
        self.waitOver = waitOver
        self.snoozedUntil = snoozedUntil
    }
}
