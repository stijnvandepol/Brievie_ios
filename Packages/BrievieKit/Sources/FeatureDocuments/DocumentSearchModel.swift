import BrievieCore
import Foundation
import Observation

/// Search in the letters of the workspace, as in the web: by text, sender, summary, labels and names. It searches
/// once the user pauses typing, and a newer term cancels the request of the older one. The term lives only here, in
/// memory: never in a log, never on disk, and it is forgotten when the user leaves "Alle post" or the session ends.
@MainActor
@Observable
public final class DocumentSearchModel {
    /// How long typing must pause before the app asks the server (which allows 30 searches a minute).
    public static let typingPause: Duration = .milliseconds(400)
    /// A shorter term finds nothing on the server either.
    static let minimumLength = 2

    public enum State: Equatable, Sendable {
        /// No term: the screen says what can be searched for.
        case idle
        /// One character: too short to search.
        case tooShort
        case searching
        case results
        case noResults
        case failed(message: String)
    }

    /// A letter that matched: the row of the post list, and where the words were found.
    public struct Hit: Equatable, Identifiable, Sendable {
        public let row: DocumentsModel.Row
        public let snippet: [SnippetPart]

        public var id: UUID { row.id }

        /// The fragment as plain text, for VoiceOver.
        public var snippetText: String { snippet.map(\.text).joined() }
    }

    /// The search field's text. Each change schedules a search (or clears the results).
    public var query = "" {
        didSet { if query != oldValue { schedule(after: delay) } }
    }

    public private(set) var state: State = .idle
    /// Nothing matched exactly: these letters have similar words ("Geen exacte treffer").
    public private(set) var isFuzzy = false
    /// The server took a BSN out of the term: Brievie keeps no BSNs, so it cannot be searched.
    public private(set) var bsnRemoved = false
    public private(set) var isLoadingMore = false

    private var found: [DocumentSearchHit] = []
    private var nextOffset: Int?
    private var persons: [Person] = []
    private var labels: [DocumentLabel] = []

    private let documents: WorkspaceDocuments
    private let onRevoked: @MainActor () -> Void
    private let onMissingPairing: @MainActor () -> Void
    private let delay: Duration
    /// Each new term or `forget()` counts up: only an answer for the current number may change the screen.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var current: Task<Void, Never>?
    /// The request a newer term cancelled; kept so tests can wait until it ended.
    @ObservationIgnored private var previous: Task<Void, Never>?

    init(
        documents: WorkspaceDocuments, onRevoked: @escaping @MainActor () -> Void,
        onMissingPairing: @escaping @MainActor () -> Void, delay: Duration
    ) {
        self.documents = documents
        self.onRevoked = onRevoked
        self.onMissingPairing = onMissingPairing
        self.delay = delay
    }

    /// The hits in the order of the server (best first), with the list's rows.
    public var hits: [Hit] {
        found.map { hit in
            Hit(
                row: DocumentsModel.row(for: hit.document, persons: persons, labels: labels), snippet: hit.snippet
            )
        }
    }

    /// The field holds a term: the screen shows the search instead of the list.
    public var isActive: Bool { !Self.term(query).isEmpty }

    public var canLoadMore: Bool { nextOffset != nil && state == .results && !isLoadingMore }

    /// The return key: search now, without waiting for the pause.
    public func submit() {
        schedule(after: .zero)
    }

    public func retry() {
        schedule(after: .zero)
    }

    /// Clears the term and the results, and drops an answer still on its way.
    public func forget() {
        query = ""
        cancel()
        clearResults(to: .idle)
    }

    public func loadMore() async {
        guard canLoadMore, let offset = nextOffset else { return }
        let generation = generation
        let text = Self.term(query)
        isLoadingMore = true
        defer { if generation == self.generation { isLoadingMore = false } }
        do {
            let page = try await documents.search(DocumentSearchQuery(text: text, offset: offset))
            guard generation == self.generation else { return }
            found += page.hits.filter { hit in !found.contains { $0.document.id == hit.document.id } }
            nextOffset = page.nextOffset
            isFuzzy = isFuzzy || page.isFuzzy
            bsnRemoved = bsnRemoved || page.bsnRemoved
        } catch {
            guard generation == self.generation else { return }
            handle(error)
        }
    }

    /// Persons and labels to name a hit's addressees and labels; the post list passes them after each load.
    func use(persons: [Person], labels: [DocumentLabel]) {
        self.persons = persons
        self.labels = labels
    }

    /// Waits for the requests of the current and the previous term (tests).
    func settle() async {
        await previous?.value
        await current?.value
    }

    /// The term as the server gets it: without spaces around it, at most the server's 200 characters.
    static func term(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(DocumentSearchQuery.maxLength))
    }

    private func cancel() {
        generation += 1
        current?.cancel()
        previous = current
        current = nil
    }

    private func schedule(after pause: Duration) {
        cancel()
        let text = Self.term(query)
        guard text.count >= Self.minimumLength else {
            clearResults(to: text.isEmpty ? .idle : .tooShort)
            return
        }
        // The rows of the previous term stay until the new answer replaces them: no flicker while typing.
        state = .searching
        let generation = generation
        current = Task { [weak self] in
            if pause > .zero {
                do { try await Task.sleep(for: pause) } catch { return }
            }
            await self?.run(text, generation: generation)
        }
    }

    private func run(_ text: String, generation: Int) async {
        do {
            let page = try await documents.search(DocumentSearchQuery(text: text))
            guard generation == self.generation else { return }
            found = page.hits
            nextOffset = page.nextOffset
            isFuzzy = page.isFuzzy
            bsnRemoved = page.bsnRemoved
            state = page.hits.isEmpty ? .noResults : .results
        } catch {
            guard generation == self.generation else { return }
            handle(error)
        }
    }

    private func handle(_ error: DocumentsError) {
        switch error {
        case .cancelled:
            return
        case .revoked:
            forget()
            onRevoked()
        case .missingPairing:
            forget()
            onMissingPairing()
        default:
            clearResults(to: .failed(message: Self.message(for: error)))
        }
    }

    private func clearResults(to state: State) {
        found = []
        nextOffset = nil
        isFuzzy = false
        bsnRemoved = false
        isLoadingMore = false
        self.state = state
    }

    static func message(for error: DocumentsError) -> String {
        switch error {
        case .tooManyRequests: DocumentStrings.searchTooMany
        case .notSupported: DocumentStrings.searchNotSupported
        default: DocumentsModel.message(for: error)
        }
    }
}
