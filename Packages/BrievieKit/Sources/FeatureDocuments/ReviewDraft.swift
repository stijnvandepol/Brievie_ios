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
}

/// Where a pre-filled value came from, kept for as long as the value is the one that was pre-filled.
public struct ValueOrigin: Equatable, Sendable {
    /// The value as it was pre-filled, in the form `Draft.text(of:)` gives.
    public let value: String
    /// The words in the letter the value was read from; empty when the AI gave none.
    public let quote: String
    /// Low confidence, flagged by the server, or no quote: the user should look twice.
    public let needsAttention: Bool
    /// Filled in by the app itself, not read from the letter: there is no confidence or quote to show.
    public let isUnchecked: Bool
}

extension ReviewModel {
    /// Below this confidence a value needs the user's attention. Equal to the server's threshold for
    /// deadlines and amounts (`NEEDS_ATTENTION_BELOW`, spec section 10), here applied to every value.
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
                needsAttention: proposal.needsAttention || proposal.confidence < ReviewModel.attentionBelow
                    || proposal.quote.isEmpty,
                isUnchecked: false
            )
            return true
        }

        mutating func markUnchecked(_ field: ReviewField, value: String) {
            origins[field] = ValueOrigin(value: value, quote: "", needsAttention: false, isUnchecked: true)
        }
    }

    static func draft(from proposals: [Proposal]) -> Draft {
        var draft = Draft()
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
    /// "1 december 2026": the day as written in Dutch, whatever the device's time zone.
    var display: String {
        let utc = TimeZone(identifier: "UTC") ?? .gmt
        let style = Date.FormatStyle(date: .long, time: .omitted, locale: Locale(identifier: "nl_NL"), timeZone: utc)
        return date(in: utc).formatted(style)
    }
}
