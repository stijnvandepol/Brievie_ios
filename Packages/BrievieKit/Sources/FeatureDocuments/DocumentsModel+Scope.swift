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
        /// When the scan was made (on the phone) or arrived (on the server): newest first within a part of a list.
        let date: Date

        init(
            id: UUID, documentID: UUID?, title: String, subtitle: String, status: RowStatus,
            addressees: [String] = [], labels: [DocumentLabel] = [], hasSuggestions: Bool = false,
            isAutomatic: Bool = false, titleIsProposal: Bool = false, date: Date = .distantPast
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
            self.date = date
        }
    }

    /// Which post the list shows.
    public enum Scope: Hashable, Sendable {
        /// "Inbox": what still needs the person (to check, a name to choose), and what is on its way.
        case inbox
        case all
        /// The post addressed to one person.
        case person(UUID)
    }
}

extension DocumentsModel.Scope {
    /// Scans still on the phone show in the inbox and in all post, not under a person.
    var showsQueue: Bool {
        !isPerson
    }

    var isPerson: Bool {
        if case .person = self { return true }
        return false
    }
}

extension DocumentsModel {
    /// The scopes for the menu: "Inbox", "Alle post", then each person who is not archived.
    public var scopeTitles: [(Scope, String)] {
        [(.inbox, DocumentStrings.scopeInbox), (.all, DocumentStrings.scopeAll)]
            + persons.filter { !$0.isArchived }.map { (.person($0.id), $0.displayName) }
    }

    /// The name of the current scope, for the navigation bar.
    public var scopeTitle: String {
        switch scope {
        case .inbox: DocumentStrings.scopeInbox
        case .all: DocumentStrings.scopeAll
        case let .person(id): persons.first { $0.id == id }?.displayName ?? DocumentStrings.section
        }
    }

    /// What the list says when the current scope has no rows.
    public var emptyText: String {
        switch scope {
        case .inbox: DocumentStrings.inboxEmpty
        case .all: DocumentStrings.empty
        case .person: DocumentStrings.personEmpty
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
        case .person: return nil
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
        if let note = status.note { parts.append(note) }
        if let addresseeLine { parts.append(addresseeLine) }
        if !labels.isEmpty {
            parts.append(String(format: DocumentStrings.labelsFormat, labels.map(\.name).joined(separator: ", ")))
        }
        if hasSuggestions { parts.append(DocumentStrings.suggestion) }
        if isAutomatic { parts.append(DocumentStrings.automaticByAI) }
        return parts.joined(separator: ", ")
    }
}

extension DocumentsModel {
    // Texts of rows and errors

    static func uploadMessage(for code: String?) -> String {
        switch code {
        case "untrusted": DocumentStrings.notVerified
        case "workspace_not_found": DocumentStrings.workspaceGone
        case "server_changed": DocumentStrings.otherServer
        case "payload_too_large": DocumentStrings.tooLarge
        default: DocumentStrings.uploadFailed
        }
    }

    static func message(for error: DocumentsError) -> String {
        switch error {
        case .unreachable: DocumentStrings.unreachable
        case .notVerified: DocumentStrings.notVerified
        case .notFound: DocumentStrings.notFound
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
