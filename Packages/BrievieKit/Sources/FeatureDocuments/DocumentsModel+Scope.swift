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

        init(
            id: UUID, documentID: UUID?, title: String, subtitle: String, status: RowStatus,
            addressees: [String] = [], labels: [DocumentLabel] = [], hasSuggestions: Bool = false
        ) {
            self.id = id
            self.documentID = documentID
            self.title = title
            self.subtitle = subtitle
            self.status = status
            self.addressees = addressees
            self.labels = labels
            self.hasSuggestions = hasSuggestions
        }
    }

    /// Which post the list shows.
    public enum Scope: Hashable, Sendable {
        /// What still needs something: to review, on nobody's name, on its way.
        case inbox
        case all
        /// The post addressed to one person.
        case person(UUID)
    }

    /// One titled part of the list. The inbox has up to three (only those with rows); the other scopes one.
    public struct RowGroup: Equatable, Identifiable, Sendable {
        public let kind: GroupKind
        public let title: String
        /// The section header: in the inbox the title with the number of rows.
        public let header: String
        public let rows: [Row]

        public var id: GroupKind { kind }
    }

    public enum GroupKind: Hashable, Sendable {
        case review
        case unassigned
        case underway
        case post
    }
}

extension DocumentsModel.Scope {
    /// Scans still on the phone show in the inbox and in all post, not under a person.
    var showsQueue: Bool {
        if case .person = self { return false }
        return true
    }
}

extension DocumentsModel {
    /// The scopes for the menu: the inbox, all post, then each person who is not archived.
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

    /// The inbox and all post share one server list; a person has their own.
    static func filter(for scope: Scope) -> DocumentFilter {
        if case let .person(id) = scope { return DocumentFilter(personID: id) }
        return .all
    }

    /// The inbox in its three groups (empty ones left out); any other scope as one group.
    func makeGroups(waiting: [Row], onServer: [(InboxState, Row)]) -> [RowGroup] {
        guard scope == .inbox else {
            let all = waiting + onServer.map(\.1)
            return [RowGroup(kind: .post, title: DocumentStrings.section, header: DocumentStrings.section, rows: all)]
        }
        func rows(in state: InboxState) -> [Row] {
            onServer.filter { $0.0 == state }.map(\.1)
        }
        func group(_ kind: GroupKind, _ title: String, _ rows: [Row]) -> RowGroup {
            RowGroup(
                kind: kind, title: title, header: String(format: DocumentStrings.groupCountFormat, title, rows.count),
                rows: rows
            )
        }
        return [
            group(.review, DocumentStrings.inboxReview, rows(in: .review)),
            group(.unassigned, DocumentStrings.inboxUnassigned, rows(in: .unassigned)),
            group(.underway, DocumentStrings.inboxUnderway, waiting + rows(in: .new))
        ].filter { !$0.rows.isEmpty }
    }
}

extension DocumentsModel.Row {
    private static let listStyle = ListFormatStyle<StringStyle, [String]>.list(type: .and)
        .locale(Locale(identifier: "nl_NL"))

    /// "Op naam van Papa en Mama"; `nil` without addressees.
    public var addresseeLine: String? {
        guard !addressees.isEmpty else { return nil }
        return String(format: DocumentStrings.addresseesFormat, addressees.formatted(Self.listStyle))
    }

    /// What VoiceOver reads for the row: sender, date and pages, status, the addressees and the labels.
    public var accessibilityLabel: String {
        var parts = [title, subtitle, status.label]
        if case let .uploadFailed(message, _) = status { parts.append(message) }
        if let addresseeLine { parts.append(addresseeLine) }
        if !labels.isEmpty {
            parts.append(String(format: DocumentStrings.labelsFormat, labels.map(\.name).joined(separator: ", ")))
        }
        if hasSuggestions { parts.append(DocumentStrings.suggestion) }
        return parts.joined(separator: ", ")
    }
}
