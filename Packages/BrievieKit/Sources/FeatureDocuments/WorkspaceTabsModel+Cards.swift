import BrievieCore
import Foundation

// The count cards on top of "Mijn post" (navigation design, section 10): unread letters, the member's tasks and,
// for sorters in an organisation, what lies too long. Each says itself in words for VoiceOver.
/// Which count a card shows.
public enum CountCardKind: Hashable, Sendable {
    case unread
    case tasks
    case lingering
}

extension WorkspaceTabsModel {
    public struct Card: Identifiable, Equatable, Sendable {
        public let kind: CountCardKind
        public let number: Int
        public let caption: String
        /// "1 te laat" under the task count; `nil` for none.
        public let detail: String?
        public let detailIsWarning: Bool
        public let accessibilityLabel: String

        public var id: CountCardKind { kind }
    }

    /// The cards of "Mijn post"; none before the numbers are known (and from an older server).
    public var cards: [Card] {
        guard let counts else { return [] }
        var cards = [
            Card(
                kind: .unread, number: counts.myPostUnread, caption: DocumentStrings.cardUnread, detail: nil,
                detailIsWarning: false, accessibilityLabel: DocumentStrings.cardUnreadLabel(counts.myPostUnread)
            )
        ]
        if hasTasks {
            let late = counts.myTasksOverdue
            cards.append(Card(
                kind: .tasks, number: counts.myTasks, caption: DocumentStrings.cardTasks,
                detail: late > 0 ? DocumentStrings.cardLateDetail(late) : nil, detailIsWarning: late > 0,
                accessibilityLabel: DocumentStrings.cardTasksLabel(counts.myTasks, late: late)
            ))
        }
        if counts.showsLingering {
            cards.append(Card(
                kind: .lingering, number: counts.lingering, caption: DocumentStrings.cardLingering, detail: nil,
                detailIsWarning: false, accessibilityLabel: DocumentStrings.cardLingeringLabel(counts.lingering)
            ))
        }
        return cards
    }

    /// The member's account has no person: "Mijn post" stays empty and says why.
    public var lacksPerson: Bool {
        counts?.hasPerson == false
    }
}
