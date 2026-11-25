import BrievieCore
import Foundation
import Observation

/// The two groups of "Blijft liggen".
public enum LingeringKind: Hashable, Sendable {
    case tooLongInInbox
    case notOpened
}

/// "Blijft liggen" (navigation design, section 6): for sorters and admins in an organisation, the letters that lie
/// too long in the Inbox and the confirmed letters their addressee has not opened yet. Only letters the member may
/// see; the server decides which and how long.
@MainActor
@Observable
public final class LingeringModel {
    public enum State: Equatable, Sendable {
        case loading
        case loaded
        case failed(message: String)
    }

    public struct Group: Identifiable, Equatable, Sendable {
        public let kind: LingeringKind
        public let title: String
        public let rows: [Item]

        public var id: LingeringKind { kind }
    }

    /// A letter with how long it lies there, in words ("Ligt er 4 dagen").
    public struct Item: Identifiable, Equatable, Sendable {
        public let row: DocumentsModel.Row
        public let age: String

        public var id: UUID { row.id }
        public var accessibilityLabel: String { "\(row.accessibilityLabel), \(age)" }
    }

    public private(set) var state: State = .loading
    public private(set) var groups: [Group] = []

    private let documents: WorkspaceDocuments
    private let persons: () -> [Person]
    private let labels: () -> [DocumentLabel]
    private let onRevoked: @MainActor () -> Void
    private let onMissingPairing: @MainActor () -> Void

    /// - Parameters:
    ///   - persons: the workspace's persons, to name the addressees (the Inbox has them).
    ///   - labels: the workspace's labels.
    public init(
        documents: WorkspaceDocuments, persons: @escaping () -> [Person], labels: @escaping () -> [DocumentLabel],
        onRevoked: @escaping @MainActor () -> Void, onMissingPairing: @escaping @MainActor () -> Void
    ) {
        self.documents = documents
        self.persons = persons
        self.labels = labels
        self.onRevoked = onRevoked
        self.onMissingPairing = onMissingPairing
    }

    public var isEmpty: Bool { groups.allSatisfy(\.rows.isEmpty) }

    public func load() async {
        do {
            let answer = try await documents.lingeringLetters()
            let persons = persons()
            let labels = labels()
            groups = [
                Group(
                    kind: .tooLongInInbox, title: DocumentStrings.lingeringTooLong,
                    rows: answer.tooLongInInbox.map { letter in
                        Item(
                            row: DocumentsModel.row(for: letter.document, persons: persons, labels: labels),
                            age: DocumentStrings.lingeringInboxDays(letter.days)
                        )
                    }
                ),
                Group(
                    kind: .notOpened, title: DocumentStrings.lingeringNotOpened,
                    rows: answer.notOpened.map { letter in
                        Item(
                            row: DocumentsModel.row(for: letter.document, persons: persons, labels: labels),
                            age: DocumentStrings.lingeringUnopenedDays(letter.days)
                        )
                    }
                )
            ].filter { !$0.rows.isEmpty }
            state = .loaded
        } catch {
            switch error {
            case .revoked: onRevoked()
            case .missingPairing: onMissingPairing()
            case .cancelled: break
            default:
                if state != .loaded { state = .failed(message: DocumentsModel.message(for: error)) }
            }
        }
    }
}
