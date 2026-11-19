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
    /// The persons and labels of the workspace, to choose from.
    public private(set) var persons: [Person] = []
    public private(set) var labels: [DocumentLabel] = []
    /// Both lists loaded: the server knows persons and labels. A 1b server does not; the review then hides
    /// "Op naam van" and "Labels" and confirms without them.
    public private(set) var organiseAvailable = false
    /// Why "Nieuwe persoon" did not work.
    public private(set) var personError: String?
    /// The confirmed letter, to change its addressees, labels and tasks; `nil` before it is confirmed and on a
    /// 1b server.
    public private(set) var confirmed: ConfirmedDocumentModel?
    /// The person or label list on screen (a sheet), in the review and on a confirmed letter.
    public var picker: OrganisePicker?
    /// The letter text with a quote marked (a sheet).
    public var shownQuote: SourceQuote?
    /// Called after the letter was confirmed and after one of its tasks was ticked off or opened again. Handed
    /// on to `confirmed` itself, so a tick that is answered after this screen closed still reaches it.
    public var onTasksChanged: (@MainActor () -> Void)? {
        didSet { confirmed?.onTasksChanged = onTasksChanged }
    }

    private let documentID: UUID
    private let documents: WorkspaceDocuments
    private let onRevoked: @MainActor () -> Void
    private let onMissingPairing: @MainActor () -> Void
    private let refreshInterval: Duration
    private let clock: TodayClock
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// The draft as it was pre-filled, to tell whether the user changed anything.
    @ObservationIgnored private var pristineDraft = Draft()
    @ObservationIgnored private var loadingPages: Set<Int> = []
    /// The lists were asked once from a server that answered: a 1b server is not asked again on every poll.
    @ObservationIgnored private var askedOrganiseLists = false

    public init(
        documentID: UUID,
        documents: WorkspaceDocuments,
        canEdit: Bool,
        onRevoked: @escaping @MainActor () -> Void,
        onMissingPairing: @escaping @MainActor () -> Void,
        refreshInterval: Duration = .seconds(3),
        clock: TodayClock = .system
    ) {
        self.documentID = documentID
        self.documents = documents
        self.canEdit = canEdit
        self.onRevoked = onRevoked
        self.onMissingPairing = onMissingPairing
        self.refreshInterval = refreshInterval
        self.clock = clock
    }

    /// The most pages the review shows of one letter. The host refuses more than 30 per letter by default
    /// (`BRIEVIE_MAX_PAGES`); this leaves room for a server set a little higher, and keeps a broken or hostile
    /// server's page count from making the screen build millions of pages.
    public static let maxPages = 50

    /// The server's page count, between 0 and `maxPages`.
    public var pageCount: Int { min(max(detail?.summary.pageCount ?? 0, 0), Self.maxPages) }
    /// The text of the pages shown, at most `maxPages`.
    public var pageTexts: [String] { Array((detail?.pageTexts ?? []).prefix(Self.maxPages)) }

    /// "Deze brief heeft 80 pagina's. Je ziet hier alleen de eerste 50."; `nil` when nothing is left out.
    public var missingPagesNote: String? {
        let total = max(detail?.summary.pageCount ?? 0, detail?.pageTexts.count ?? 0)
        guard total > Self.maxPages else { return nil }
        return String(format: DocumentStrings.missingPagesFormat, total, Self.maxPages)
    }
    /// Processing failed on the server; the review can still be filled in by hand.
    public var processingFailed: Bool { detail?.summary.status == .failed }

    /// The screen's title: "Brief" for a confirmed letter, "Controleren" otherwise.
    public var title: String {
        state == .done ? DocumentStrings.letterTitle : DocumentStrings.reviewTitle
    }

    /// Loads the letter; the persons and labels the first time, and again for a confirmed letter (a label made
    /// in the web meanwhile shows in the picker). Lists that cannot be loaded again keep the ones on screen.
    public func load() async {
        let asksLists = !askedOrganiseLists
        let refreshesLists = !asksLists && organiseAvailable && state == .done
        async let lists = asksLists || refreshesLists ? Self.organiseLists(from: documents) : nil
        do {
            let detail = try await documents.detail(documentID)
            if asksLists {
                askedOrganiseLists = true
                apply(await lists)
            } else if refreshesLists, detail.summary.status == .done, let fresh = await lists {
                apply(fresh)
                confirmed?.showLists(persons: fresh.persons, labels: fresh.labels)
            }
            show(detail)
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

    /// Back in the foreground: look again while the letter is processed. Leaving it: a sheet sits above the lock
    /// screen and the app-switcher cover, so the letter text, the names, the labels and a half-typed new person
    /// close; no polling while nobody looks either. The draft stays.
    public func sceneDidChange(isActive: Bool) {
        if isActive {
            startPolling()
        } else {
            picker = nil
            shownQuote = nil
            stopPolling()
        }
    }

    /// Opens the person or label list. An error of an earlier "Nieuwe persoon" no longer applies.
    public func pick(_ picker: OrganisePicker) {
        if picker == .persons { personError = nil }
        self.picker = picker
    }

    /// Shows where `quote` stands in the letter.
    public func showQuote(_ quote: String) {
        shownQuote = SourceQuote(text: quote)
    }

    public func loadPage(_ index: Int) async {
        // Only the pages the screen shows (1 through `pageCount`).
        guard (1...Self.maxPages).contains(index), index <= pageCount, pages[index] == nil,
              !loadingPages.contains(index) else { return }
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
            summary: draft.summary, summaryByAI: draft.summaryIsByAI, tasks: draft.tasks,
            addresseeIDs: organiseAvailable ? Self.sorted(draft.organise.addresseeIDs) : [],
            labelIDs: organiseAvailable ? Self.sorted(draft.organise.labelIDs) : [],
            setsOrganisation: organiseAvailable
        )
        do {
            show(try await documents.confirm(documentID, review: review))
            onTasksChanged?()
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
        case .notFound where organiseAvailable:
            await handleMissingChoice()
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

    private func confirmedModel(_ detail: DocumentDetail) -> ConfirmedDocumentModel {
        let model = ConfirmedDocumentModel(
            detail: detail, persons: persons, labels: labels, documents: documents, canEdit: canEdit,
            onRevoked: onRevoked, onMissingPairing: onMissingPairing
        )
        model.onTasksChanged = onTasksChanged
        return model
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
                draft = Self.draft(from: detail, today: clock.today)
                pristineDraft = draft
            }
            state = .review
        case .done:
            if !organiseAvailable {
                confirmed = nil
            } else if let confirmed, confirmed.detail.summary.id == detail.summary.id {
                // Keep the model: its message and the changes on their way stay with it.
                confirmed.show(detail)
            } else {
                confirmed = confirmedModel(detail)
            }
            state = .done
        case .unknown:
            state = .done
        }
    }
}

// MARK: - Organise

extension ReviewModel {
    /// Adds a person to the workspace and puts the letter on their name. Returns whether it worked.
    @discardableResult
    public func createPerson(named name: String) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canEdit, !name.isEmpty else { return false }
        personError = nil
        do {
            let person = try await documents.createPerson(named: name)
            persons.append(person)
            draft.organise.addresseeIDs.insert(person.id)
            return true
        } catch .nameTaken {
            personError = DocumentStrings.nameTaken
            // Probably made in the web meanwhile: show them in the list.
            if let fresh = try? await documents.persons() { persons = fresh }
        } catch {
            handle(error) { personError = DocumentsModel.message(for: $0) }
        }
        return false
    }

    /// Confirm found no such person or label, or no such document. A document that is still there means a
    /// chosen person or label was deleted meanwhile: keep the draft without it and let the user look again.
    /// Only the document's own `.notFound` leaves the review; any other failure keeps the draft as it is.
    private func handleMissingChoice() async {
        let detail: DocumentDetail
        do {
            detail = try await documents.detail(documentID)
        } catch .notFound {
            state = .failed(message: DocumentsModel.message(for: .notFound))
            return
        } catch {
            handle(error) { saveError = DocumentsModel.message(for: $0) }
            return
        }
        show(detail)
        guard state == .review else { return }
        guard let lists = await Self.organiseLists(from: documents) else {
            // Nothing new to check against: keep the lists and the choice, and say it did not work.
            saveError = DocumentStrings.generic
            return
        }
        apply(lists)
        draft.organise.setAddressees(draft.organise.addresseeIDs.intersection(persons.map(\.id)))
        draft.organise.setLabels(draft.organise.labelIDs.intersection(labels.map(\.id)))
        saveError = DocumentStrings.organiseGone
    }

    /// Both lists, or `nil` when either could not be loaded (a 1b server has neither).
    private nonisolated static func organiseLists(
        from documents: WorkspaceDocuments
    ) async -> (persons: [Person], labels: [DocumentLabel])? {
        async let persons = try? documents.persons()
        async let labels = try? documents.labels()
        guard let persons = await persons, let labels = await labels else { return nil }
        return (persons, labels)
    }

    private func apply(_ lists: (persons: [Person], labels: [DocumentLabel])?) {
        persons = lists?.persons ?? []
        labels = lists?.labels ?? []
        organiseAvailable = lists != nil
    }

    private static func sorted(_ ids: Set<UUID>) -> [UUID] {
        ids.sorted { $0.uuidString < $1.uuidString }
    }
}
