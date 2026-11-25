import Foundation

/// Where "Mijn taken" puts a task, as the server decides it (in Europe/Amsterdam). The app never recounts it.
public enum TaskGroup: String, Equatable, Sendable, CaseIterable {
    case overdue
    case withinWeek = "within_week"
    case later
    case noDate = "no_date"
    /// "Wacht op reactie" (only with `include_waiting`, host PR #50).
    case waiting
    /// "Uitgesteld", for this member (only with `include_waiting`).
    case snoozed
    /// The server did not say (an older server, or a list that has no groups).
    case none = ""
    /// A group this app does not know yet.
    case unknown

    public init(api: String) {
        self = Self(rawValue: api) ?? .unknown
    }
}

/// Why a task is on the member's own list, as the server decides it.
public enum TaskReason: String, Equatable, Sendable {
    /// The member was given the task (or took it).
    case assigned
    /// The member is an addressee of the letter.
    case addressee
    /// The task belongs to a department the member is in.
    case department
    /// Nobody has the task and the letter has no addressee.
    case unassigned
    case other
    case none = ""
    case unknown

    public init(api: String) {
        self = Self(rawValue: api) ?? .unknown
    }
}

/// Which tasks `listMyTasks` returns: the member's own, those nobody has picked up yet, or all they may see.
public enum MyTasksPart: String, Equatable, Sendable {
    case mine
    case toPickUp = "to_pick_up"
    case all
}

public enum MyTasksStatus: String, Equatable, Sendable {
    case open
    /// Ticked off in the last 30 days.
    case done
}

/// One answer of `listMyTasks`.
public struct MyTasks: Equatable, Sendable {
    public let items: [WorkspaceTask]
    /// Today in Europe/Amsterdam, by the server's clock.
    public let today: CalendarDate
    /// False when the member's account is not linked to a person: their own list can then be short.
    public let hasPerson: Bool
    /// More than the server's cap (500) matched; `items` holds the first ones.
    public let truncated: Bool
    /// Letters that still wait for a review the member may do; new tasks may come out of them.
    public let waitingLetters: Int
    /// The workspace splits tasks over people (an organisation): there is a "to pick up" part.
    public let split: Bool

    public init(
        items: [WorkspaceTask], today: CalendarDate, hasPerson: Bool = true, truncated: Bool = false,
        waitingLetters: Int = 0, split: Bool = false
    ) {
        self.items = items
        self.today = today
        self.hasPerson = hasPerson
        self.truncated = truncated
        self.waitingLetters = waitingLetters
        self.split = split
    }
}

/// The counts of `countMyTasks`, for the menu and the Inbox's link.
public struct MyTaskCounts: Equatable, Sendable {
    public let mine: Int
    public let overdue: Int
    public let withinWeek: Int
    public let needsDate: Int
    public let toPickUp: Int
    /// Own tasks that wait for a reply, and those this member snoozed (0 from a server before host PR #50).
    public let waiting: Int
    public let snoozed: Int

    public init(
        mine: Int, overdue: Int = 0, withinWeek: Int = 0, needsDate: Int = 0, toPickUp: Int = 0, waiting: Int = 0,
        snoozed: Int = 0
    ) {
        self.mine = mine
        self.overdue = overdue
        self.withinWeek = withinWeek
        self.needsDate = needsDate
        self.toPickUp = toPickUp
        self.waiting = waiting
        self.snoozed = snoozed
    }
}

/// Someone a task can be handed to: a member who may read the task's letter. Names only.
public struct TaskAssignee: Identifiable, Equatable, Sendable {
    /// The user's id.
    public let id: UUID
    public let name: String
    public let isMe: Bool

    public init(id: UUID, name: String, isMe: Bool) {
        self.id = id
        self.name = name
        self.isMe = isMe
    }
}
