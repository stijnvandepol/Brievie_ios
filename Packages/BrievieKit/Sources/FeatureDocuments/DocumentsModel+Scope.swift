import BrievieCore
import Foundation

extension DocumentsModel {
    public struct Row: Equatable, Identifiable, Sendable {
        /// The server's id, or the queue item's id while the scan is still on the phone.
        public let id: UUID
        /// `nil` while the scan has not reached the server: there is nothing to open yet.
        public let documentID: UUID?
        public let title: String
        public let subtitle: String
        public let status: RowStatus
        /// Display names of the persons the letter is addressed to, in the order of the persons list.
        public let addressees: [String]
        /// In the order of the labels list.
        public let labels: [DocumentLabel]
        /// The server has open proposals for addressees or labels.
        public let hasSuggestions: Bool
        /// `title` is the sender the AI proposed, not a confirmed one: shown as "(voorstel)", never as a fact.
        public let titleIsProposal: Bool
        /// The AI confirmed the letter, or put a label or name on it, by itself: "Automatisch door AI".
        public let isAutomatic: Bool
        /// The letter is in an open duplicate pair: the chip "Dubbel?".
        public let isPossibleDuplicate: Bool
        /// "Ongelezen": the member has not opened it. Never in the Inbox, which is a to-do list, not news.
        public let isUnread: Bool
        /// The letter's status and "Te laat" (host PR #50); `nil` from an older server and for scans.
        public let letterBadge: LetterBadge?
        /// When the scan was made (on the phone) or arrived (on the server): newest first within a part of a list.
        let date: Date

        init(
            id: UUID, documentID: UUID?, title: String, subtitle: String, status: RowStatus,
            addressees: [String] = [], labels: [DocumentLabel] = [], hasSuggestions: Bool = false,
            isAutomatic: Bool = false, titleIsProposal: Bool = false, isPossibleDuplicate: Bool = false,
            isUnread: Bool = false, letterBadge: LetterBadge? = nil, date: Date = .distantPast
        ) {
            self.id = id
            self.documentID = documentID
            self.title = title
            self.subtitle = subtitle
            self.status = status
            self.addressees = addressees
            self.labels = labels
            self.hasSuggestions = hasSuggestions
            self.isAutomatic = isAutomatic
            self.titleIsProposal = titleIsProposal
            self.isPossibleDuplicate = isPossibleDuplicate
            self.isUnread = isUnread
            self.letterBadge = letterBadge
            self.date = date
        }
    }

    /// Which post the list shows.
    public enum Scope: Hashable, Sendable {
        /// "Inbox": what still needs the person (to check, a name to choose), and what is on its way.
        case inbox
        /// "Mijn post": the letters addressed to the member's own person (the app's start screen).
        case myPost
        /// "Mijn post" with "Alleen ongelezen".
        case myPostUnread
        case all
        /// The post addressed to one person ("Voor wie" in "Alle post").
        case person(UUID)
        /// The letters with one label (Meer, Labels).
        case label(UUID)
    }
}

extension DocumentsModel.Scope {
    /// Scans still on the phone show in the inbox and in all post: they have no addressee yet.
    var showsQueue: Bool {
        self == .inbox || self == .all
    }

    var isPerson: Bool {
        if case .person = self { return true }
        return false
    }
}

extension DocumentsModel {
    /// The choices of "Voor wie" in "Alle post": everyone, then each person who is not archived.
    public var forWhomChoices: [(Scope, String)] {
        [(.all, DocumentStrings.forEveryone)]
            + persons.filter { !$0.isArchived }.map { (.person($0.id), $0.displayName) }
    }

    /// "Voor wie" applies: the screen shows "Alle post" or one person's post.
    public var offersForWhom: Bool {
        scope == .all || scope.isPerson
    }

    /// "Mijn post", with or without "Alleen ongelezen".
    public var isMyPost: Bool {
        scope == .myPost || scope == .myPostUnread
    }

    /// The name of the current scope, for the navigation bar.
    public var scopeTitle: String {
        switch scope {
        case .inbox: DocumentStrings.scopeInbox
        case .myPost, .myPostUnread: DocumentStrings.scopeMyPost
        case .all: DocumentStrings.scopeAll
        case let .person(id): persons.first { $0.id == id }?.displayName ?? DocumentStrings.section
        case let .label(id): labels.first { $0.id == id }?.name ?? DocumentStrings.labelsTitle
        }
    }

    /// "Naam kiezen" in the Inbox: the first letter on screen that waits for a name; `nil` for none.
    public var firstLetterNeedingName: UUID? {
        rows.first { $0.status == .needsName }?.documentID
    }

    /// The list shows its empty text: no rows and, in "Te doen", no pairs either.
    public var showsEmpty: Bool { rows.isEmpty && duplicates.isEmpty }

    /// What the list says when the current scope has no rows.
    public var emptyText: String {
        switch scope {
        case .inbox: DocumentStrings.inboxEmpty
        case .myPost: DocumentStrings.myPostEmpty
        case .myPostUnread: DocumentStrings.myPostAllRead
        case .all: DocumentStrings.empty
        case .person: DocumentStrings.personEmpty
        case .label: DocumentStrings.labelEmpty
        }
    }

    /// Under the empty "Inbox": what to do next. A viewer is not told to scan.
    public var emptyHint: String? {
        guard scope == .inbox else { return nil }
        return canScan ? DocumentStrings.todoEmptyHintScan : DocumentStrings.todoEmptyHint
    }

    /// Search belongs to "Alle post": the other scopes are short lists of their own.
    public var searchIsAvailable: Bool { scope == .all }

    /// The empty "Inbox" offers a way to "Alle post".
    public var emptyOffersAllPost: Bool { scope == .inbox }

    /// Under a list with rows: what this place is for, and where the rest is. `nil` for a person's post.
    public var footer: String? {
        guard !rows.isEmpty else { return nil }
        switch scope {
        case .inbox: return DocumentStrings.todoFooter
        case .all: return DocumentStrings.allFooter
        case .myPost, .myPostUnread, .person, .label: return nil
        }
    }

    /// Whether `source` still belongs to the current scope: an answer for a scope the user left is dropped.
    func isCurrent(_ source: Source) -> Bool {
        Self.source(for: scope) == source
    }

    /// False for a person scope whose person is not among `persons` or is archived.
    func isActivePersonScope(in persons: [Person]) -> Bool {
        guard case let .person(id) = scope else { return true }
        return persons.contains { $0.id == id && !$0.isArchived }
    }

    nonisolated static func persons(of documents: WorkspaceDocuments, if wanted: Bool) async -> [Person]? {
        guard wanted else { return nil }
        return try? await documents.persons()
    }

    nonisolated static func labels(of documents: WorkspaceDocuments, if wanted: Bool) async -> [DocumentLabel]? {
        guard wanted else { return nil }
        return try? await documents.labels()
    }

    /// The rows in the order of the scope. "Inbox": what needs the person first (to check, a name to choose, a
    /// failed upload), then what is on its way (scans still on the phone, letters being read), each part newest
    /// first. Any other scope: the scans on the phone, then the server's letters, each newest first.
    func arrange(waiting: [Row], onServer: [Row]) -> [Row] {
        let newestFirst = { (lhs: Row, rhs: Row) in
            lhs.date != rhs.date ? lhs.date > rhs.date : lhs.id.uuidString < rhs.id.uuidString
        }
        guard scope == .inbox else {
            return waiting.sorted(by: newestFirst) + onServer.sorted(by: newestFirst)
        }
        let all = waiting + onServer
        return all.filter { !$0.status.isUnderway }.sorted(by: newestFirst)
            + all.filter(\.status.isUnderway).sorted(by: newestFirst)
    }

    /// The line above "Inbox", in the rows' words: "Controleren: 2 · Naam kiezen: 1 · Bezig: 3". `totals` is
    /// the number per state the server counted; a part with more letters than shown says it shows the newest.
    /// `nil` without rows.
    static func todoSummary(waiting: [Row], onServer: [InboxState], totals: [InboxState: Int]) -> String? {
        func shown(_ state: InboxState) -> Int { onServer.count { $0 == state } }
        func total(_ state: InboxState) -> Int { max(totals[state] ?? shown(state), shown(state)) }
        let failedUploads = waiting.count { !$0.status.isUnderway }
        let waitingUploads = waiting.count - failedUploads
        let parts = [
            SummaryPart(word: DocumentStrings.statusNeedsReview, total: total(.review), shown: shown(.review)),
            SummaryPart(word: DocumentStrings.statusNeedsName, total: total(.unassigned), shown: shown(.unassigned)),
            SummaryPart(word: DocumentStrings.statusUploadFailed, total: failedUploads, shown: failedUploads),
            SummaryPart(
                word: DocumentStrings.summaryUnderway, total: total(.new) + waitingUploads,
                shown: shown(.new) + waitingUploads
            )
        ]
        let text = parts.filter { $0.total > 0 }.map { part in
            part.total > part.shown
                ? String(format: DocumentStrings.summaryPartialFormat, part.word, part.total, part.shown)
                : String(format: DocumentStrings.summaryCountFormat, part.word, part.total)
        }
        return text.isEmpty ? nil : text.joined(separator: " · ")
    }
}

/// One part of the line above "Inbox": a row word, how many there are and how many the list shows.
private struct SummaryPart {
    let word: String
    let total: Int
    let shown: Int
}

extension DocumentsModel.Row {
    /// "Papa and Mama" or "Papa en Mama": the list word follows the user's language.
    private static var listStyle: ListFormatStyle<StringStyle, [String]> {
        .list(type: .and).locale(.autoupdatingCurrent)
    }

    /// "Op naam van Papa en Mama"; `nil` without addressees.
    public var addresseeLine: String? {
        guard !addressees.isEmpty else { return nil }
        return String(format: DocumentStrings.addresseesFormat, addressees.formatted(Self.listStyle))
    }

    /// What VoiceOver reads for the row: sender, date and pages, status and its note, the addressees and the labels.
    public var accessibilityLabel: String {
        var parts = [titleIsProposal ? "\(title) \(DocumentStrings.proposedMark)" : title, subtitle, status.label]
        if isUnread { parts.insert(DocumentStrings.unread, at: 0) }
        if let letterBadge { parts.insert(letterBadge.accessibilityText, at: isUnread ? 2 : 1) }
        if let note = status.note { parts.append(note) }
        if let addresseeLine { parts.append(addresseeLine) }
        if !labels.isEmpty {
            parts.append(String(format: DocumentStrings.labelsFormat, labels.map(\.name).joined(separator: ", ")))
        }
        if hasSuggestions { parts.append(DocumentStrings.suggestion) }
        if isAutomatic { parts.append(DocumentStrings.automaticByAI) }
        if isPossibleDuplicate { parts.append(DocumentStrings.duplicateChip) }
        return parts.joined(separator: ", ")
    }
}

extension DocumentsModel {
    // Texts of rows and errors

    /// A letter's row in the words of the list; the search shows its hits with the same row.
    static func row(
        for document: DocumentSummary, persons: [Person], labels: [DocumentLabel], showsUnread: Bool = false
    ) -> Row {
        let addressees = Set(document.addresseeIDs)
        let labelIDs = Set(document.labelIDs)
        let status = Self.status(of: document)
        let (title, isProposal) = Self.title(of: document, status: status)
        return Row(
            id: document.id, documentID: document.id, title: title,
            subtitle: Self.subtitle(date: document.createdAt, pages: document.pageCount),
            status: status,
            addressees: persons.filter { addressees.contains($0.id) }.map(\.displayName),
            labels: labels.filter { labelIDs.contains($0.id) },
            hasSuggestions: document.openSuggestionCount > 0,
            isAutomatic: document.isAutomatic, titleIsProposal: isProposal,
            isPossibleDuplicate: document.isPossibleDuplicate, isUnread: showsUnread && document.isUnread,
            letterBadge: LetterStatusWords.badge(for: document), date: document.createdAt
        )
    }

    /// Upload failures that a retry cannot fix: the scan can only be deleted.
    static let finalUploadCodes: Set<String> = ["server_changed", "document_trashed"]

    static func uploadMessage(for code: String?) -> String {
        switch code {
        case "untrusted": DocumentStrings.notVerified
        case "workspace_not_found": DocumentStrings.workspaceGone
        case "server_changed": DocumentStrings.otherServer
        case "payload_too_large": DocumentStrings.tooLarge
        case "document_trashed": DocumentStrings.uploadTrashed
        default: DocumentStrings.uploadFailed
        }
    }

    static func message(for error: DocumentsError) -> String {
        switch error {
        case .unreachable: DocumentStrings.unreachable
        case .notVerified: DocumentStrings.notVerified
        case .notFound: DocumentStrings.notFound
        case .forbidden: DocumentStrings.forbidden
        case .busy: DocumentStrings.busy
        case .inTrash: DocumentStrings.inTrash
        case .secondFactorRequired: DocumentStrings.secondFactorRequired
        default: DocumentStrings.generic
        }
    }

    /// The letter's date in the user's language and region ("12 nov 2026", "12 Nov 2026", "Nov 12, 2026").
    static var dateStyle: Date.FormatStyle {
        Date.FormatStyle(date: .abbreviated, time: .omitted, locale: .autoupdatingCurrent)
    }

    /// A letter the server read but nobody checked yet has no sender in the list (the AI's proposal is only in
    /// the detail): it is named by the time it came in, so letters of one day can be told apart.
    /// The row's title and whether it is a proposal: the confirmed sender; for a letter to check without one the
    /// sender the AI proposed (when the server lists it), else the time it came in.
    static func title(of document: DocumentSummary, status: RowStatus) -> (String, isProposal: Bool) {
        if !document.sender.isEmpty { return (document.sender, false) }
        let proposed = document.proposedSender.trimmingCharacters(in: .whitespacesAndNewlines)
        if !proposed.isEmpty, status == .needsReview || status == .failed { return (proposed, true) }
        return (untitled(status, arrived: document.createdAt), false)
    }

    static func untitled(_ status: RowStatus, arrived: Date) -> String {
        switch status {
        case .processing: DocumentStrings.newDocument
        case .needsReview, .failed:
            String(format: DocumentStrings.arrivedFormat, arrived.formatted(date: .omitted, time: .shortened))
        default: DocumentStrings.unknownSender
        }
    }

    static func subtitle(date: Date, pages: Int) -> String {
        let pageText = pages == 1 ? DocumentStrings.pagesOne : String(format: DocumentStrings.pagesManyFormat, pages)
        return "\(date.formatted(dateStyle)) · \(pageText)"
    }
}
