import Foundation

/// An open task with a deadline, as the event it should be in the workspace's calendar.
public struct CalendarTask: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let notes: String
    public let day: CalendarDate

    public init(id: UUID, title: String, notes: String, day: CalendarDate) {
        self.id = id
        self.title = title
        self.notes = notes
        self.day = day
    }

    /// "<taaksoort>: <omschrijving>" on the deadline, with the sender and "Uit Brievie" as notes. `nil` for a
    /// task that is done or has no deadline: it has no event.
    /// - Parameter typeTitle: the Dutch name of a task type code.
    public static func from(_ task: WorkspaceTask, typeTitle: (String) -> String) -> CalendarTask? {
        guard !task.isDone, let deadline = task.deadline else { return nil }
        let sender = task.sender.trimmingCharacters(in: .whitespacesAndNewlines)
        let footer = AppStrings.calendarNotesFooter
        return CalendarTask(
            id: task.id,
            title: "\(typeTitle(task.type)): \(task.description)",
            notes: sender.isEmpty ? footer : "\(sender)\n\(footer)",
            day: deadline
        )
    }
}

/// An all-day event in a Brievie calendar, as the sync reads it.
public struct CalendarEventSnapshot: Equatable, Sendable {
    public let eventID: String
    /// From the event's URL `brievie://task/<uuid>`; `nil` for an event the user added by hand.
    public let taskID: UUID?
    public let title: String
    public let notes: String
    public let day: CalendarDate

    public init(eventID: String, taskID: UUID?, title: String, notes: String, day: CalendarDate) {
        self.eventID = eventID
        self.taskID = taskID
        self.title = title
        self.notes = notes
        self.day = day
    }
}

/// One write to a Brievie calendar.
public enum CalendarChange: Equatable, Sendable {
    case create(CalendarTask)
    case update(eventID: String, CalendarTask)
    case delete(eventID: String)
}

/// The outcome of a sync, for the switch on the Workspaces screen.
public enum CalendarSyncResult: Equatable, Sendable {
    /// The switch is off for this workspace: nothing was read or written.
    case off
    /// Brievie may not use the calendar: nothing was written.
    case noAccess
    case done(created: Int, updated: Int, deleted: Int)
    /// The server has no task list (a 1b server): no calendar was made.
    case tasksNotSupported
    case failed
}

/// The link in an event that ties it to its task: `brievie://task/<uuid>`.
public enum TaskLink {
    public static let scheme = "brievie"

    public static func url(for taskID: UUID) -> URL? {
        URL(string: "\(scheme)://task/\(taskID.uuidString.lowercased())")
    }

    /// The task of a Brievie task link; `nil` for any other URL.
    public static func taskID(in url: URL?) -> UUID? {
        guard let url, url.scheme?.lowercased() == scheme, url.host() == "task" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1 else { return nil }
        return UUID(uuidString: parts[0])
    }
}
