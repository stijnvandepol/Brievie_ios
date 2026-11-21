import BrievieCore
import Foundation
import Observation

/// The compare screen of two letters that look scanned twice: the first page and the facts of both side by side,
/// what differs marked, and the two answers: "Het is dezelfde brief" (merge) and "Het zijn twee brieven"
/// (dismiss). A viewer only looks.
@MainActor
@Observable
public final class DuplicateModel {
    public enum State: Equatable, Sendable {
        case loading
        case loaded
        /// The server has no such open pair (404): decided and gone, or never visible.
        case gone(message: String)
        case failed(message: String)
        /// Merged, dismissed, or decided elsewhere: the screen closes itself.
        case finished
    }

    /// How a compare row is marked: the server found the values differ, or could not read one of them well.
    public enum Mark: Equatable, Sendable {
        case differs
        case mayDiffer
    }

    /// One fact of both letters: "Afzender", "Brief 1: …", "Brief 2: …", and a mark when they differ.
    public struct CompareRow: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let first: String
        public let second: String
        public let mark: Mark?

        /// "Verschilt", "Verschilt misschien (slecht leesbaar)", or `nil`.
        public var markText: String? {
            switch mark {
            case .differs: DocumentStrings.duplicateDiffers
            case .mayDiffer: DocumentStrings.duplicateMayDiffer
            case nil: nil
            }
        }

        /// One VoiceOver element: "Afzender. Brief 1: Gemeente. Brief 2: CAK. Verschilt".
        public var accessibilityLabel: String {
            let first = String(format: DocumentStrings.duplicateLetterFormat, 1)
            let second = String(format: DocumentStrings.duplicateLetterFormat, 2)
            let values = "\(title). \(first): \(self.first). \(second): \(self.second)."
            return markText.map { "\(values) \($0)" } ?? values
        }
    }

    /// The head of one letter's column: "Brief 1", when it was scanned, and the labels of its page and its choice.
    public struct Letter: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let scanned: String
        /// "Eerste pagina van brief 1".
        public let pageLabel: String
        /// "Deze brief houden: brief 1".
        public let keepLabel: String
    }

    public private(set) var state: State = .loading
    public private(set) var pair: DuplicatePair?
    /// Each letter's detail (tasks, page texts), loaded beside the pair; a letter that failed is missing.
    public private(set) var details: [UUID: DocumentDetail] = [:]
    /// Each letter's first page; a page that failed is missing (the screen shows a placeholder).
    public private(set) var firstPages: [UUID: Data] = [:]
    /// The details and first pages were asked for: a page still missing failed.
    public private(set) var lettersLoaded = false
    /// The letter to keep: the server's suggestion until the user picks the other one.
    public var keepID: UUID
    public private(set) var isSaving = false
    /// Why an answer did not work, or that the pair was decided elsewhere.
    public private(set) var message: String?
    /// "Samenvoegen?" is asked (a sheet, so it closes when the app leaves the foreground).
    public var asksToMerge = false
    /// "Taak ook afronden": on each time the question opens.
    public var completeTwinTasks = true
    /// One letter on the whole screen (pushed); `nil` when closed.
    public private(set) var reader: DuplicateLetterReader?
    /// Members and admins choose; a viewer only looks.
    public let canEdit: Bool
    public let pairID: UUID

    let documents: WorkspaceDocuments
    let persons: [Person]
    let labels: [DocumentLabel]
    let locale: Locale
    private let onMerged: @MainActor (UUID) -> Void
    private let onDismissed: @MainActor () -> Void
    private let onDecidedElsewhere: @MainActor () -> Void
    private let onRevoked: @MainActor () -> Void
    private let onMissingPairing: @MainActor () -> Void
    /// The server refused a merge because the letters are not visible to the same people.
    private var mergeRefused = false

    /// - Parameter locale: the language of the dates and amounts; the user's own by default.
    public init(
        pairID: UUID,
        documents: WorkspaceDocuments,
        canEdit: Bool,
        persons: [Person],
        labels: [DocumentLabel],
        onMerged: @escaping @MainActor (UUID) -> Void,
        onDismissed: @escaping @MainActor () -> Void,
        onDecidedElsewhere: @escaping @MainActor () -> Void,
        onRevoked: @escaping @MainActor () -> Void,
        onMissingPairing: @escaping @MainActor () -> Void,
        locale: Locale = .autoupdatingCurrent
    ) {
        self.pairID = pairID
        // A placeholder until the pair is loaded; `merge()` only sends one of the pair's letters.
        keepID = pairID
        self.documents = documents
        self.canEdit = canEdit
        self.persons = persons
        self.labels = labels
        self.onMerged = onMerged
        self.onDismissed = onDismissed
        self.onDecidedElsewhere = onDecidedElsewhere
        self.onRevoked = onRevoked
        self.onMissingPairing = onMissingPairing
        self.locale = locale
    }

    /// "Het is dezelfde brief" is offered: a member or admin, a pair the server can merge.
    public var canMerge: Bool {
        canEdit && state == .loaded && pair?.canMerge == true && !mergeRefused
    }

    /// The answers are offered at all ("Het zijn twee brieven" stays when merging cannot).
    public var canDecide: Bool { canEdit && state == .loaded }

    /// Why "Het is dezelfde brief" is gone; `nil` when it is offered, and for a viewer (who has no answers).
    public var blockedNote: String? {
        guard canEdit, let pair, !pair.canMerge || mergeRefused else { return nil }
        return DocumentStrings.duplicateVisibilityDiffers
    }

    /// One line per task that is done on the other scan and still open on the letter kept. The switch "Taak ook
    /// afronden" shows only when there is one.
    public var twinNotes: [String] {
        (pair?.taskTwins ?? []).filter { $0.openDocumentID == keepID }.map {
            String(format: DocumentStrings.duplicateTwinNoteFormat, $0.description)
        }
    }

    /// Loads the pair, then each letter's detail and first page side by side.
    public func load() async {
        do {
            let fresh = try await documents.duplicate(pairID)
            if pair == nil || ![fresh.first.id, fresh.second.id].contains(keepID) {
                keepID = fresh.suggestedKeepID
            }
            pair = fresh
            state = .loaded
            await loadLetters(of: fresh)
        } catch .notFound {
            state = .gone(message: DocumentStrings.duplicateGone)
        } catch {
            handle(error) { error in
                if pair == nil { state = .failed(message: DocumentsModel.message(for: error)) }
            }
        }
    }

    /// "Het is dezelfde brief": asks first, with "Taak ook afronden" switched on again.
    public func askToMerge() {
        guard canMerge else { return }
        completeTwinTasks = true
        asksToMerge = true
    }

    /// "Samenvoegen": one request, also when tapped twice. Sends the switch only when it showed; otherwise the
    /// server's default (complete the twin tasks).
    public func merge() async {
        asksToMerge = false
        guard canMerge, !isSaving, let pair, [pair.first.id, pair.second.id].contains(keepID) else { return }
        let completes = twinNotes.isEmpty ? true : completeTwinTasks
        let other = keepID == pair.first.id ? pair.second.id : pair.first.id
        isSaving = true
        message = nil
        defer { isSaving = false }
        do {
            _ = try await documents.mergeDuplicate(pairID, keep: keepID, completeTwinTasks: completes)
            state = .finished
            onMerged(other)
        } catch {
            handleDecisionFailure(error)
        }
    }

    /// "Het zijn twee brieven": the server does not ask again about these two letters.
    public func dismiss() async {
        guard canDecide, !isSaving else { return }
        isSaving = true
        message = nil
        defer { isSaving = false }
        do {
            try await documents.dismissDuplicate(pairID)
            state = .finished
            onDismissed()
        } catch {
            handleDecisionFailure(error)
        }
    }

    /// Leaving the foreground closes the merge question (a sheet sits above the lock screen).
    public func sceneDidChange(isActive: Bool) {
        if !isActive { asksToMerge = false }
    }

    /// Shows one letter of the pair on the whole screen.
    public func openReader(_ documentID: UUID) {
        guard let pair, [pair.first.id, pair.second.id].contains(documentID) else { return }
        let summary = documentID == pair.first.id ? pair.first : pair.second
        let detail = details[documentID]
        reader = DuplicateLetterReader(
            documentID: documentID, pageCount: detail?.summary.pageCount ?? summary.pageCount,
            pageTexts: detail?.pageTexts ?? [], firstPage: firstPages[documentID], documents: documents,
            onClose: { [weak self] in self?.reader = nil }, onRevoked: onRevoked, onMissingPairing: onMissingPairing
        )
    }

    public func closeReader() {
        reader = nil
    }

    // MARK: - Private

    private func handleDecisionFailure(_ error: DocumentsError) {
        switch error {
        case .alreadyDecided:
            message = DocumentStrings.duplicateDecided
            state = .finished
            onDecidedElsewhere()
        case .visibilityDiffers:
            mergeRefused = true
        case .notFound:
            state = .gone(message: DocumentStrings.duplicateGone)
        default:
            handle(error) { message = DocumentsModel.message(for: $0) }
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

    private func loadLetters(of pair: DuplicatePair) async {
        let answers = await withTaskGroup(of: LetterAnswer.self) { [documents] group in
            for id in [pair.first.id, pair.second.id] {
                group.addTask { await Self.fetchLetter(id, from: documents) }
            }
            var answers: [LetterAnswer] = []
            for await answer in group { answers.append(answer) }
            return answers
        }
        for answer in answers {
            if case let .success(detail) = answer.detail { details[answer.id] = detail }
            if case let .success(page) = answer.page { firstPages[answer.id] = page }
        }
        lettersLoaded = true
        // A failing letter leaves a placeholder; an ended session still ends here.
        let errors = answers.flatMap { [$0.detail.failure, $0.page.failure].compactMap(\.self) }
        if errors.contains(.revoked) {
            onRevoked()
        } else if errors.contains(.missingPairing) {
            onMissingPairing()
        }
    }

    private struct LetterAnswer: Sendable {
        let id: UUID
        let detail: Result<DocumentDetail, DocumentsError>
        let page: Result<Data, DocumentsError>
    }

    private nonisolated static func fetchLetter(_ id: UUID, from documents: WorkspaceDocuments) async -> LetterAnswer {
        async let detail = Self.result { () async throws(DocumentsError) in try await documents.detail(id) }
        async let page = Self.result { () async throws(DocumentsError) in try await documents.pageImage(id, index: 1) }
        return LetterAnswer(id: id, detail: await detail, page: await page)
    }

    private nonisolated static func result<Value: Sendable>(
        _ work: () async throws(DocumentsError) -> Value
    ) async -> Result<Value, DocumentsError> {
        do {
            return .success(try await work())
        } catch {
            return .failure(error)
        }
    }
}

private extension Result {
    var failure: Failure? {
        if case let .failure(error) = self { return error }
        return nil
    }
}
