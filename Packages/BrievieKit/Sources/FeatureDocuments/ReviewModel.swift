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

    public private(set) var state: State = .loading
    public var draft = Draft()
    public private(set) var detail: DocumentDetail?
    /// Page images by 1-based page number. In memory only.
    public private(set) var pages: [Int: Data] = [:]
    public private(set) var isSaving = false
    public private(set) var saveError: String?
    /// "Opnieuw verwerken" was asked while the draft holds the user's own changes: the screen asks first.
    public private(set) var confirmsDiscardingEdits = false
    /// Members and admins confirm; a viewer only reads.
    public let canEdit: Bool

    private let documentID: UUID
    private let documents: WorkspaceDocuments
    private let onRevoked: @MainActor () -> Void
    private let onMissingPairing: @MainActor () -> Void
    private let refreshInterval: Duration
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// The draft as it was pre-filled, to tell whether the user changed anything.
    @ObservationIgnored private var pristineDraft = Draft()
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
        draft.tasks.append(Self.emptyTask())
    }

    public func removeTask(_ id: UUID) {
        draft.tasks.removeAll { $0.id == id }
    }

    /// A deadline the user changed is theirs: its source in the letter no longer belongs to it. Setting the
    /// date read from the letter again brings its source back.
    public func setDeadline(_ deadline: CalendarDate?, for taskID: UUID) {
        guard let index = draft.tasks.firstIndex(where: { $0.id == taskID }),
              draft.tasks[index].deadline != deadline
        else { return }
        draft.tasks[index].deadline = deadline
        draft.syncDeadlineSource(of: index)
    }

    /// The user changed something since the draft was pre-filled (or started empty).
    public var draftHasUserEdits: Bool { draft != pristineDraft }

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

    /// Processing again replaces the draft. When the user changed it, the screen asks first
    /// (`confirmsDiscardingEdits`) and calls again with `discardingEdits`.
    public func retryProcessing(discardingEdits: Bool = false) async {
        guard canEdit, !isSaving else { return }
        guard discardingEdits || !draftHasUserEdits else {
            confirmsDiscardingEdits = true
            return
        }
        confirmsDiscardingEdits = false
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            show(try await documents.retryProcessing(documentID))
        } catch {
            await handleSaveFailure(error)
        }
    }

    public func keepEdits() {
        confirmsDiscardingEdits = false
    }

    // MARK: - Private

    private func handleSaveFailure(_ error: DocumentsError) async {
        switch error {
        case .conflict:
            // Confirmed or changed elsewhere: show what the server has now. Still waiting for review (the
            // edits are kept): say that it did not work.
            await load()
            if state == .review { saveError = DocumentStrings.confirmConflict }
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
            if !wasReviewing {
                draft = Self.draft(from: detail.proposals)
                pristineDraft = draft
            }
            state = .review
        case .done, .unknown:
            state = .done
        }
    }
}
