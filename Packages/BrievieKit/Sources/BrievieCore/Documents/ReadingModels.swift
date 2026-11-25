import Foundation

/// The numbers of the menu for one workspace (`getMenuCounts`, host PR #44). Every number is of this workspace only.
public struct MenuCounts: Equatable, Sendable {
    /// Letters in the Inbox that still need someone: to check, or a name to choose.
    public let inbox: Int
    /// "Ongelezen" letters in "Mijn post".
    public let myPostUnread: Int
    /// The member's own open tasks, and how many of them are past their deadline.
    public let myTasks: Int
    public let myTasksOverdue: Int
    /// "Blijft liggen": letters that lie too long in the Inbox or were not opened by their addressee.
    public let lingering: Int
    /// The member sorts post in an organisation: "Blijft liggen" applies to them (also when it is 0).
    public let showsLingering: Bool
    /// The member's account is linked to a person; without one "Mijn post" stays empty.
    public let hasPerson: Bool

    public init(
        inbox: Int = 0, myPostUnread: Int = 0, myTasks: Int = 0, myTasksOverdue: Int = 0, lingering: Int = 0,
        showsLingering: Bool = false, hasPerson: Bool = true
    ) {
        self.inbox = inbox
        self.myPostUnread = myPostUnread
        self.myTasks = myTasks
        self.myTasksOverdue = myTasksOverdue
        self.lingering = lingering
        self.showsLingering = showsLingering
        self.hasPerson = hasPerson
    }
}

/// One letter of "Blijft liggen": the letter and how many days it lies there (in the Inbox, or not opened).
public struct LingeringLetter: Equatable, Sendable, Identifiable {
    public let document: DocumentSummary
    public let days: Int

    public var id: UUID { document.id }

    public init(document: DocumentSummary, days: Int) {
        self.document = document
        self.days = days
    }
}

/// `listLingeringLetters`: the two groups of "Blijft liggen" and the workspace's thresholds.
public struct LingeringLetters: Equatable, Sendable {
    public let tooLongInInbox: [LingeringLetter]
    public let notOpened: [LingeringLetter]
    public let inboxDays: Int
    public let unopenedDays: Int

    public var isEmpty: Bool { tooLongInInbox.isEmpty && notOpened.isEmpty }

    public init(tooLongInInbox: [LingeringLetter], notOpened: [LingeringLetter], inboxDays: Int, unopenedDays: Int) {
        self.tooLongInInbox = tooLongInInbox
        self.notOpened = notOpened
        self.inboxDays = inboxDays
        self.unopenedDays = unopenedDays
    }
}

/// What the server lets the member do with a task (host PR #44): pick up one nobody has, hand it over, release it.
/// A colleague's task is never picked up by a member; only that person or an admin hands it on.
public struct TaskPermissions: Equatable, Sendable {
    public let canTake: Bool
    public let canHandOver: Bool
    public let canRelease: Bool

    public init(canTake: Bool = false, canHandOver: Bool = false, canRelease: Bool = false) {
        self.canTake = canTake
        self.canHandOver = canHandOver
        self.canRelease = canRelease
    }

    /// `nil` when the server sent none of the three (a server before host PR #44).
    init?(take: Bool?, handOver: Bool?, release: Bool?) {
        guard take != nil || handOver != nil || release != nil else { return nil }
        self.init(canTake: take ?? false, canHandOver: handOver ?? false, canRelease: release ?? false)
    }
}
