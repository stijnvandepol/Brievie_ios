import Foundation

/// An open task of a workspace, as the reminders see it.
public struct ReminderTask: Equatable, Sendable {
    public let workspaceID: UUID
    public let task: WorkspaceTask

    public init(workspaceID: UUID, task: WorkspaceTask) {
        self.workspaceID = workspaceID
        self.task = task
    }
}

/// Which workspace and task a reminder belongs to, read back from its identifier.
public struct ReminderIdentity: Equatable, Hashable, Sendable {
    public let workspaceID: UUID
    public let taskID: UUID
}

/// A local notification for a task's deadline, as it should be pending on the phone.
public struct DeadlineReminder: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// Some days before the deadline (the lead time is a setting).
        case ahead
        /// On the day of the deadline.
        case onTheDay = "day"
        /// "Wachten voorbij": on the day a task's waiting for a reply ends (host PR #50).
        case waitOver = "waitover"
    }

    /// `deadline.<workspace>.<task>.<kind>`: the same task and kind always replace the same reminder.
    public let identifier: String
    public let workspaceID: UUID
    public let taskID: UUID
    /// The letter the task belongs to: tapping the reminder opens it.
    public let documentID: UUID?
    public let kind: Kind
    /// The day it goes off, at `hour`:`minute` local time.
    public let day: CalendarDate
    public let hour: Int
    public let minute: Int
    /// The moment in the time zone it was planned in: for the order and for "already passed".
    public let fireDate: Date
    /// The only text on the lock screen. Nothing from the letter, unless the user chose to show the sender.
    public let body: String
}

/// Which reminders exist for a task list. Pure: the clock, the time zone and the settings come in.
///
/// For every open task with a deadline that has not passed: one reminder `leadDays` before (none when that is 0)
/// and one on the day, both at 09:00 in `timeZone`. A reminder whose moment has passed is left out (the lead day
/// of a deadline that is close, the day itself after nine). iOS keeps at most 64 pending local notifications per
/// app, so the nearest `limit` are kept; the rest follow at a later refresh, once the nearest have gone off.
public enum ReminderPlanner {
    /// The most local notifications iOS keeps pending for one app.
    public static let maxPending = 64
    /// The local time a reminder goes off.
    public static let hour = 9
    public static let minute = 0
    /// The lead times the settings offer, in days before the deadline; 0 is "on the day only".
    public static let leadOptions = [0, 1, 2, 3, 7]
    public static let defaultLeadDays = 3
    /// A sender longer than this is cut, so the reminder stays one short sentence.
    static let maxSenderLength = 40

    private static let prefix = "deadline"

    /// The reminders for `tasks`, without memory of earlier catch-ups (see `schedule`).
    public static func plan(
        _ tasks: [ReminderTask], now: Date, timeZone: TimeZone, leadDays: Int, showsSender: Bool,
        limit: Int = maxPending
    ) -> [DeadlineReminder] {
        schedule(tasks, now: now, timeZone: timeZone, leadDays: leadDays, showsSender: showsSender, limit: limit)
            .reminders
    }

    /// The reminders for `tasks` and the catch-ups to remember. A task whose first notice has passed while its
    /// day has not gets one catch-up at the next 09:00 instead (`catchUp(for:)`), unless that is the day itself.
    /// - Parameter catchUps: the catch-ups planned before; one whose moment has passed is not made again.
    public static func schedule(
        _ tasks: [ReminderTask], now: Date, timeZone: TimeZone, leadDays: Int, showsSender: Bool,
        catchUps: [ReminderIdentity: CatchUp] = [:], limit: Int = maxPending
    ) -> ReminderPlan {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let context = CatchUpContext(now: now, calendar: calendar, leadDays: leadDays, earlier: catchUps)
        let candidates = tasks.flatMap { item -> [DeadlineReminder] in
            guard !item.task.isDone, item.task.group != .snoozed else { return [] }
            let sender = showsSender ? shortSender(item.task.sender) : nil
            // A task that waits for a reply gets no deadline reminder, only one on the day the waiting ends.
            if item.task.group == .waiting {
                guard let until = item.task.waitingUntil else { return [] }
                return [reminder(item, kind: .waitOver, day: until, sender: sender, calendar: calendar)]
                    .filter { $0.fireDate > now }
            }
            guard let deadline = item.task.deadline else { return [] }
            var reminders = [reminder(item, kind: .onTheDay, day: deadline, sender: sender, calendar: calendar)]
            if let first = firstNotice(for: item, deadline: deadline, context: context) {
                reminders.insert(reminder(item, kind: .ahead, day: first, sender: sender, calendar: calendar), at: 0)
            }
            return reminders.filter { $0.fireDate > now }
        }
        let kept = Array(candidates.sorted(by: isSooner).prefix(max(limit, 0)))
        return ReminderPlan(
            reminders: kept, catchUps: remembered(catchUps, tasks: tasks, kept: kept, context: context)
        )
    }

    /// The workspace and task of one of Brievie's reminder identifiers; `nil` for any other identifier.
    public static func parse(_ identifier: String) -> ReminderIdentity? {
        let parts = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == prefix, DeadlineReminder.Kind(rawValue: String(parts[3])) != nil,
              let workspace = UUID(uuidString: String(parts[1])), let task = UUID(uuidString: String(parts[2]))
        else { return nil }
        return ReminderIdentity(workspaceID: workspace, taskID: task)
    }

    static func identifier(workspace: UUID, task: UUID, kind: DeadlineReminder.Kind) -> String {
        "\(prefix).\(workspace.uuidString.lowercased()).\(task.uuidString.lowercased()).\(kind.rawValue)"
    }

    /// The reminder of `kind` going off on `day`; the days left until the deadline follow from the two.
    static func reminder(
        _ item: ReminderTask, kind: DeadlineReminder.Kind, day: CalendarDate, sender: String?, calendar: Calendar
    ) -> DeadlineReminder {
        let daysLeft = kind == .onTheDay ? 0 : daysBetween(day, item.task.deadline ?? day)
        let components = DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute)
        return DeadlineReminder(
            identifier: identifier(workspace: item.workspaceID, task: item.task.id, kind: kind),
            workspaceID: item.workspaceID, taskID: item.task.id, documentID: item.task.documentID, kind: kind,
            day: day, hour: hour, minute: minute, fireDate: calendar.date(from: components) ?? .distantPast,
            body: kind == .waitOver ? waitOverBody(sender: sender) : body(daysLeft: daysLeft, sender: sender)
        )
    }

    private static func daysBetween(_ start: CalendarDate, _ end: CalendarDate) -> Int {
        var days = 0
        var day = start
        while day < end {
            day = day.adding(days: 1)
            days += 1
        }
        return days
    }

    /// "Een termijn loopt over 3 dagen af.", or with the sender when the user chose so.
    static func body(daysLeft: Int, sender: String?) -> String {
        switch (daysLeft, sender) {
        case (0, nil): AppStrings.reminderToday
        case (1, nil): AppStrings.reminderTomorrow
        case (_, nil): String(format: AppStrings.reminderInDaysFormat, daysLeft)
        case let (0, sender?): String(format: AppStrings.reminderSenderTodayFormat, sender)
        case let (1, sender?): String(format: AppStrings.reminderSenderTomorrowFormat, sender)
        case let (_, sender?): String(format: AppStrings.reminderSenderInDaysFormat, sender, daysLeft)
        }
    }

    static func waitOverBody(sender: String?) -> String {
        sender.map { String(format: AppStrings.reminderSenderWaitOverFormat, $0) } ?? AppStrings.reminderWaitOver
    }

    /// The sender on one line, cut when long; `nil` when there is none.
    private static func shortSender(_ sender: String) -> String? {
        let line = sender.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        guard line.count > maxSenderLength else { return line }
        return line.prefix(maxSenderLength).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The nearest first; the same moment in a fixed order, so the same list always keeps the same 64.
    private static func isSooner(_ lhs: DeadlineReminder, _ rhs: DeadlineReminder) -> Bool {
        if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
        return lhs.identifier < rhs.identifier
    }
}
