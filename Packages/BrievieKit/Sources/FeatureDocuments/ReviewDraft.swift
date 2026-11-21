import BrievieCore
import Foundation

/// A value of the review the user confirms.
public enum ReviewField: Hashable, Sendable {
    case sender
    case documentType
    case letterDate
    case taskType(UUID)
    case taskDescription(UUID)
    case taskDeadline(UUID)
    case taskAmount(UUID)

    /// The value stands in the letter itself, so a quote and a confidence say something about it. A type or
    /// a task's text is the AI's own wording: the server gives those a fixed confidence and no quote.
    var isReadFromLetter: Bool {
        switch self {
        case .sender, .letterDate, .taskDeadline, .taskAmount: true
        case .documentType, .taskType, .taskDescription: false
        }
    }
}

/// Where a pre-filled value came from, kept for as long as the value is the one that was pre-filled.
public struct ValueOrigin: Equatable, Sendable {
    /// The value as it was pre-filled, in the form `Draft.text(of:)` gives.
    public let value: String
    /// The words in the letter the value was read from; empty when the AI gave none.
    public let quote: String
    /// Flagged by the server, or read from the letter with low confidence or without a quote: the user
    /// should look twice.
    public let needsAttention: Bool
    /// Filled in by the app itself, not read from the letter: there is no confidence or quote to show.
    public let isUnchecked: Bool
    /// Today's date, filled in by the app because nothing else was there: a starting value, not a reading.
    public var isToday = false
}

/// What "today" is for a letter date that starts empty: the day it is now in the user's time zone.
public struct TodayClock: Sendable {
    let now: @Sendable () -> Date
    let timeZone: @Sendable () -> TimeZone

    public init(now: @escaping @Sendable () -> Date, timeZone: @escaping @Sendable () -> TimeZone) {
        self.now = now
        self.timeZone = timeZone
    }

    /// The device's clock and time zone, read at the moment the draft is made.
    public static let system = TodayClock(now: { Date() }, timeZone: { .current })

    var today: CalendarDate { CalendarDate(now(), in: timeZone()) }
}

extension ReviewModel {
    /// Below this confidence a value read from the letter needs the user's attention. Equal to the server's
    /// threshold for deadlines and amounts (`NEEDS_ATTENTION_BELOW`, spec section 10).
    nonisolated static let attentionBelow = Decimal(string: "0.85") ?? 1

    /// What the user is about to confirm, pre-filled from the proposals.
    public struct Draft: Equatable, Sendable {
        public var sender = ""
        public var documentType = ""
        public var letterDate: CalendarDate?
        public var summary = ""
        /// The AI's own summary, to tell whether `summary` is still its text.
        public var aiSummary = ""
        public var tasks: [TaskDraft] = []
        /// AI values that were not found in the letter (confidence 0), ready to read: shown as a hint, never
        /// pre-filled.
        public var unverified: [ReviewField: String] = [:]
        /// Where each pre-filled value came from.
        public internal(set) var origins: [ReviewField: ValueOrigin] = [:]
        /// On whose name the letter is and its labels.
        public var organise = OrganiseDraft()

        public init() {}

        public var summaryIsByAI: Bool { !aiSummary.isEmpty && summary == aiSummary }

        /// The draft was pre-filled from AI proposals (as opposed to started empty, by hand).
        public internal(set) var isFromAI = false

        /// The origin of a field while it still holds the pre-filled value. A value the user changed is
        /// theirs: it has no quote and no mark; typing the original back brings them back.
        public func origin(of field: ReviewField) -> ValueOrigin? {
            guard let origin = origins[field], text(of: field) == origin.value else { return nil }
            return origin
        }

        public func quote(for field: ReviewField) -> String { origin(of: field)?.quote ?? "" }
        public func needsAttention(_ field: ReviewField) -> Bool { origin(of: field)?.needsAttention ?? false }
        public func isUnchecked(_ field: ReviewField) -> Bool { origin(of: field)?.isUnchecked ?? false }
        /// The field still holds the date of today the app filled in.
        public func isToday(_ field: ReviewField) -> Bool { origin(of: field)?.isToday ?? false }

        public var senderQuote: String { quote(for: .sender) }
        public var letterDateQuote: String { quote(for: .letterDate) }

        /// The current value of a field as text; `nil` for a task that is gone.
        func text(of field: ReviewField) -> String? {
            switch field {
            case .sender: return sender
            case .documentType: return documentType
            case .letterDate: return letterDate?.iso ?? ""
            case let .taskType(id): return tasks.first { $0.id == id }?.type
            case let .taskDescription(id): return tasks.first { $0.id == id }?.description
            case let .taskDeadline(id): return tasks.first { $0.id == id }.map { $0.deadline?.iso ?? "" }
            case let .taskAmount(id): return tasks.first { $0.id == id }?.amount
            }
        }

        /// Keeps a task's deadline source in step with its value: the quote only while it is the date read
        /// from the letter.
        mutating func syncDeadlineSource(of index: Int) {
            let origin = origin(of: .taskDeadline(tasks[index].id))
            let quote = origin?.quote ?? ""
            tasks[index].deadlineSource = quote.isEmpty ? "manual" : "in_document"
            tasks[index].deadlineQuote = quote
            tasks[index].needsAttention = origin?.needsAttention ?? false
        }

        /// Pre-fills `field` with `text` when the letter supports the proposal at all; otherwise only the
        /// hint `hint`. Returns whether the field was filled.
        mutating func propose(_ proposal: Proposal, for field: ReviewField, text: String?, hint: String) -> Bool {
            guard proposal.confidence > 0, let text, !text.isEmpty else {
                if !hint.isEmpty { unverified[field] = hint }
                return false
            }
            origins[field] = ValueOrigin(
                value: text, quote: proposal.quote,
                needsAttention: proposal.needsAttention || field.isReadFromLetter
                    && (proposal.confidence < ReviewModel.attentionBelow || proposal.quote.isEmpty),
                isUnchecked: false
            )
            return true
        }

        mutating func markUnchecked(_ field: ReviewField, value: String) {
            origins[field] = ValueOrigin(value: value, quote: "", needsAttention: false, isUnchecked: true)
        }
    }

    /// The draft for `detail`. An empty letter date starts as `today`, unless the AI proposed one (also one it
    /// could not find in the letter: that stays a hint) or the server stored one; nothing is sent before the
    /// user confirms.
    static func draft(
        from detail: DocumentDetail, today: CalendarDate, locale: Locale = .autoupdatingCurrent
    ) -> Draft {
        let proposals = detail.proposals
        var draft = Draft()
        draft.organise = OrganiseDraft(detail: detail)
        draft.isFromAI = !proposals.isEmpty
        for proposal in proposals where proposal.group == 0 {
            addDocumentValue(proposal, to: &draft)
        }
        let groups = Set(proposals.map(\.group)).filter { $0 > 0 }.sorted()
        for group in groups {
            addTask(from: proposals.filter { $0.group == group }, to: &draft)
        }
        if let due = proposals.first(where: { $0.field == "invoice_due_date" }),
           !draft.tasks.contains(where: { $0.type == "pay" }) {
            // The app adds this task: its type and text are not read from the letter, only the date is.
            var pay = emptyTask()
            pay.type = "pay"
            pay.description = DocumentStrings.payInvoice
            draft.tasks.append(pay)
            draft.markUnchecked(.taskType(pay.id), value: pay.type)
            draft.markUnchecked(.taskDescription(pay.id), value: pay.description)
            apply(deadline: due, toTaskAt: draft.tasks.count - 1, in: &draft)
        }
        if let amount = proposals.first(where: { $0.field == "invoice_amount_incl" && $0.group == 0 }) {
            apply(amount: amount, locale: locale, in: &draft)
        }
        if draft.letterDate == nil, draft.unverified[.letterDate] == nil {
            if let stored = detail.summary.letterDate {
                draft.letterDate = stored
            } else {
                draft.letterDate = today
                draft.origins[.letterDate] = ValueOrigin(
                    value: today.iso, quote: "", needsAttention: false, isUnchecked: false, isToday: true
                )
            }
        }
        return draft
    }

    static func emptyTask() -> TaskDraft {
        TaskDraft(
            type: "other", description: "", deadline: nil, deadlineSource: "manual", deadlineQuote: "",
            needsAttention: false
        )
    }

    private static func addDocumentValue(_ proposal: Proposal, to draft: inout Draft) {
        switch proposal.field {
        case "sender":
            if draft.propose(proposal, for: .sender, text: proposal.value, hint: proposal.value) {
                draft.sender = proposal.value
            }
        case "document_type":
            let code = DocumentTypes.knownDocumentType(proposal.value)
            let hint = DocumentTypes.documentTypeLabel(code)
            if draft.propose(proposal, for: .documentType, text: code, hint: hint) {
                draft.documentType = code
            }
        case "letter_date":
            let date = CalendarDate(iso: proposal.value)
            let hint = date?.display ?? proposal.value
            if draft.propose(proposal, for: .letterDate, text: date?.iso, hint: hint) {
                draft.letterDate = date
            }
        case "summary":
            draft.summary = proposal.value
            draft.aiSummary = proposal.value
        default:
            break
        }
    }

    private static func addTask(from proposals: [Proposal], to draft: inout Draft) {
        draft.tasks.append(emptyTask())
        let index = draft.tasks.count - 1
        let id = draft.tasks[index].id
        for proposal in proposals {
            switch proposal.field {
            case "action_type":
                let code = DocumentTypes.knownTaskType(proposal.value)
                let hint = DocumentTypes.taskTypeLabel(code)
                if draft.propose(proposal, for: .taskType(id), text: code, hint: hint) {
                    draft.tasks[index].type = code
                }
            case "action_description":
                if draft.propose(proposal, for: .taskDescription(id), text: proposal.value, hint: proposal.value) {
                    draft.tasks[index].description = proposal.value
                }
            case "action_deadline":
                apply(deadline: proposal, toTaskAt: index, in: &draft)
            default:
                break
            }
        }
    }

    /// The invoice's amount on the payment task, in the user's notation ("1.234,56"), with its quote.
    private static func apply(amount proposal: Proposal, locale: Locale, in draft: inout Draft) {
        guard let index = draft.tasks.firstIndex(where: { $0.type == "pay" }) else { return }
        let text = TaskAmount.parse(api: proposal.value)?
            .formatted(.number.precision(.fractionLength(2)).locale(locale))
        if draft.propose(proposal, for: .taskAmount(draft.tasks[index].id), text: text, hint: text ?? proposal.value) {
            draft.tasks[index].amount = text ?? ""
        }
    }

    /// A date the letter does not support (confidence 0) is not pre-filled: the user types it.
    private static func apply(deadline proposal: Proposal, toTaskAt index: Int, in draft: inout Draft) {
        let date = CalendarDate(iso: proposal.value)
        let field = ReviewField.taskDeadline(draft.tasks[index].id)
        if draft.propose(proposal, for: field, text: date?.iso, hint: date?.display ?? proposal.value) {
            draft.tasks[index].deadline = date
        }
        draft.syncDeadlineSource(of: index)
    }
}

extension CalendarDate {
    /// "1 december 2026" or "1 December 2026": the day as written in the user's language, whatever the device's
    /// time zone.
    var display: String { display(locale: .autoupdatingCurrent) }

    func display(locale: Locale) -> String {
        let utc = TimeZone(identifier: "UTC") ?? .gmt
        let style = Date.FormatStyle(date: .long, time: .omitted, locale: locale, timeZone: utc)
        return date(in: utc).formatted(style)
    }
}
