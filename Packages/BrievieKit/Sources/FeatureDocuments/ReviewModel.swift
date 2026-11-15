import BrievieCore
import Foundation
import Observation

/// One document: what the server proposes, what the user makes of it, and the confirmation that turns it
/// into tasks. The AI proposes; nothing becomes a task before the user confirms.
@MainActor
@Observable
public final class ReviewModel {
    public enum State: Equatable, Sendable {
        case loading
        /// The server is still reading the letter.
        case processing
        /// The draft can be edited and confirmed (also after processing failed: then by hand).
        case review
        case done
        case failed(message: String)
    }

    /// What the user is about to confirm, pre-filled from the proposals.
    public struct Draft: Equatable, Sendable {
        public var sender = ""
        /// The words in the letter the sender was read from; empty when typed by hand.
        public var senderQuote = ""
        public var documentType = ""
        public var letterDate: CalendarDate?
        public var letterDateQuote = ""
        public var summary = ""
        /// The AI's own summary, to tell whether `summary` is still its text.
        public var aiSummary = ""
        public var tasks: [TaskDraft] = []
        /// AI values that were not found in the letter, by field: shown as a hint, never pre-filled.
        public var unverified: [String: String] = [:]

        public init() {}

        public var summaryIsByAI: Bool { !aiSummary.isEmpty && summary == aiSummary }
    }

    public private(set) var state: State = .loading
    public var draft = Draft()
    public private(set) var detail: DocumentDetail?
    /// Page images by 1-based page number. In memory only.
    public private(set) var pages: [Int: Data] = [:]
    public private(set) var isSaving = false
    public private(set) var saveError: String?
    /// Members and admins confirm; a viewer only reads.
    public let canEdit: Bool

    private let documentID: UUID
    private let documents: WorkspaceDocuments
    private let onRevoked: @MainActor () -> Void
    private let onMissingPairing: @MainActor () -> Void
    private let refreshInterval: Duration
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var loadingPages: Set<Int> = []

    public init(
        documentID: UUID,
        documents: WorkspaceDocuments,
        canEdit: Bool,
        onRevoked: @escaping @MainActor () -> Void,
        onMissingPairing: @escaping @MainActor () -> Void,
        refreshInterval: Duration = .seconds(3)
    ) {
        self.documentID = documentID
        self.documents = documents
        self.canEdit = canEdit
        self.onRevoked = onRevoked
        self.onMissingPairing = onMissingPairing
        self.refreshInterval = refreshInterval
    }

    public var pageCount: Int { detail?.summary.pageCount ?? 0 }
    public var pageTexts: [String] { detail?.pageTexts ?? [] }
    /// Processing failed on the server; the review can still be filled in by hand.
    public var processingFailed: Bool { detail?.summary.status == .failed }

    public func load() async {
        do {
            show(try await documents.detail(documentID))
        } catch {
            handle(error) { state = .failed(message: DocumentsModel.message(for: $0)) }
        }
    }

    /// While the server is reading the letter: look again.
    public func refreshIfProcessing() async {
        guard state == .processing else { return }
        await load()
    }

    public func startPolling() {
        stopPolling()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: refreshInterval)
                if Task.isCancelled { return }
                await refreshIfProcessing()
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func loadPage(_ index: Int) async {
        guard pages[index] == nil, !loadingPages.contains(index) else { return }
        loadingPages.insert(index)
        defer { loadingPages.remove(index) }
        do {
            pages[index] = try await documents.pageImage(documentID, index: index)
        } catch {
            // The page stays a placeholder; a 401 still ends the session.
            handle(error) { _ in }
        }
    }

    public func addTask() {
        draft.tasks.append(TaskDraft(
            type: "other", description: "", deadline: nil, deadlineSource: "manual", deadlineQuote: "",
            needsAttention: false
        ))
    }

    public func removeTask(_ id: UUID) {
        draft.tasks.removeAll { $0.id == id }
    }

    /// A deadline the user changed is theirs: its source in the letter no longer belongs to it.
    public func setDeadline(_ deadline: CalendarDate?, for taskID: UUID) {
        guard let index = draft.tasks.firstIndex(where: { $0.id == taskID }),
              draft.tasks[index].deadline != deadline
        else { return }
        draft.tasks[index].deadline = deadline
        draft.tasks[index].deadlineSource = "manual"
        draft.tasks[index].deadlineQuote = ""
        draft.tasks[index].needsAttention = false
    }

    public func confirm() async {
        guard canEdit, state == .review, !isSaving else { return }
        guard draft.tasks.allSatisfy({ !$0.description.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            saveError = DocumentStrings.taskNeedsDescription
            return
        }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let review = ConfirmedReview(
            sender: draft.sender, documentType: draft.documentType, letterDate: draft.letterDate,
            summary: draft.summary, summaryByAI: draft.summaryIsByAI, tasks: draft.tasks
        )
        do {
            show(try await documents.confirm(documentID, review: review))
        } catch {
            await handleSaveFailure(error)
        }
    }

    public func retryProcessing() async {
        guard canEdit, !isSaving else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            show(try await documents.retryProcessing(documentID))
        } catch {
            await handleSaveFailure(error)
        }
    }

    // MARK: - Private

    private func handleSaveFailure(_ error: DocumentsError) async {
        switch error {
        case .conflict:
            // Confirmed or changed elsewhere: show what the server has now.
            await load()
        case .invalid:
            saveError = DocumentStrings.reviewRefused
        default:
            handle(error) { saveError = DocumentsModel.message(for: $0) }
        }
    }

    private func handle(_ error: DocumentsError, otherwise: (DocumentsError) -> Void) {
        switch error {
        case .revoked: onRevoked()
        case .missingPairing: onMissingPairing()
        case .cancelled: break
        default: otherwise(error)
        }
    }

    private func show(_ detail: DocumentDetail) {
        let wasReviewing = state == .review && self.detail?.summary.status == detail.summary.status
        self.detail = detail
        switch detail.summary.status {
        case .processing:
            state = .processing
        case .needsReview, .failed:
            // A refresh must not throw away what the user typed.
            if !wasReviewing { draft = Self.draft(from: detail.proposals) }
            state = .review
        case .done, .unknown:
            state = .done
        }
    }

    static func draft(from proposals: [Proposal]) -> Draft {
        var draft = Draft()
        for proposal in proposals where proposal.group == 0 {
            let trusted = proposal.confidence > 0
            switch proposal.field {
            case "sender":
                if trusted {
                    draft.sender = proposal.value
                    draft.senderQuote = proposal.quote
                } else {
                    draft.unverified["sender"] = proposal.value
                }
            case "document_type":
                draft.documentType = DocumentTypes.knownDocumentType(proposal.value)
            case "letter_date":
                if trusted, let date = CalendarDate(iso: proposal.value) {
                    draft.letterDate = date
                    draft.letterDateQuote = proposal.quote
                } else {
                    draft.unverified["letter_date"] = proposal.value
                }
            case "summary":
                draft.summary = proposal.value
                draft.aiSummary = proposal.value
            default:
                break
            }
        }
        let groups = Set(proposals.map(\.group)).filter { $0 > 0 }.sorted()
        draft.tasks = groups.map { group in task(from: proposals.filter { $0.group == group }) }
        if let due = proposals.first(where: { $0.field == "invoice_due_date" }),
           !draft.tasks.contains(where: { $0.type == "pay" }) {
            var pay = task(from: [])
            pay.type = "pay"
            pay.description = DocumentStrings.payInvoice
            apply(deadline: due, to: &pay)
            draft.tasks.append(pay)
        }
        return draft
    }

    private static func task(from proposals: [Proposal]) -> TaskDraft {
        var task = TaskDraft(
            type: "other", description: "", deadline: nil, deadlineSource: "manual", deadlineQuote: "",
            needsAttention: false
        )
        for proposal in proposals {
            switch proposal.field {
            case "action_type": task.type = DocumentTypes.knownTaskType(proposal.value)
            case "action_description": task.description = proposal.value
            case "action_deadline": apply(deadline: proposal, to: &task)
            default: break
            }
        }
        return task
    }

    /// A date the letter does not support (confidence 0) is not pre-filled: the user types it.
    private static func apply(deadline proposal: Proposal, to task: inout TaskDraft) {
        task.needsAttention = proposal.needsAttention
        guard proposal.confidence > 0, let date = CalendarDate(iso: proposal.value) else {
            task.needsAttention = true
            return
        }
        task.deadline = date
        if !proposal.quote.isEmpty {
            task.deadlineSource = "in_document"
            task.deadlineQuote = proposal.quote
        }
    }
}
