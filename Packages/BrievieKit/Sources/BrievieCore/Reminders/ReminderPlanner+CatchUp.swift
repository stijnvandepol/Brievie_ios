import Foundation

/// A first notice made late: its planned day had passed when the task became known, so it goes off at the next
/// 09:00 instead. Remembered, so it is made once: a later refresh after it went off does not make another.
public struct CatchUp: Equatable, Sendable {
    /// The day it goes off.
    public let day: CalendarDate
    /// The deadline it was made for: a moved deadline starts afresh.
    public let deadline: CalendarDate

    public init(day: CalendarDate, deadline: CalendarDate) {
        self.day = day
        self.deadline = deadline
    }
}

/// What `ReminderPlanner.schedule` returns: the reminders to have pending, and the catch-ups to remember.
public struct ReminderPlan: Equatable, Sendable {
    public let reminders: [DeadlineReminder]
    public let catchUps: [ReminderIdentity: CatchUp]
}

/// What deciding a first notice needs besides the task.
struct CatchUpContext {
    let now: Date
    let calendar: Calendar
    let leadDays: Int
    let earlier: [ReminderIdentity: CatchUp]

    /// 09:00 on `day` in the planning time zone.
    func nine(on day: CalendarDate) -> Date {
        let components = DateComponents(
            year: day.year, month: day.month, day: day.day, hour: ReminderPlanner.hour, minute: ReminderPlanner.minute
        )
        return calendar.date(from: components) ?? .distantPast
    }

    var today: CalendarDate { CalendarDate(now, in: calendar.timeZone) }
}

extension ReminderPlanner {
    /// The day of a task's first notice, or `nil` for none. The planned day (`leadDays` before) while its 09:00 is
    /// ahead; once that has passed, one catch-up at the next 09:00 (today if it is still before nine, else
    /// tomorrow), never on the deadline itself (that day has its own) and never a second time.
    static func firstNotice(for item: ReminderTask, deadline: CalendarDate, context: CatchUpContext) -> CalendarDate? {
        guard context.leadDays > 0 else { return nil }
        let planned = deadline.adding(days: -context.leadDays)
        if context.nine(on: planned) > context.now { return planned }
        let identity = ReminderIdentity(workspaceID: item.workspaceID, taskID: item.task.id)
        if let earlier = context.earlier[identity], earlier.deadline == deadline {
            // Made before: still ahead, it stays on its day; gone off, it is not made again.
            return context.nine(on: earlier.day) > context.now ? earlier.day : nil
        }
        let today = context.today
        let next = context.nine(on: today) > context.now ? today : today.adding(days: 1)
        return next < deadline ? next : nil
    }

    /// The catch-ups to remember: those of tasks that are still open with the same deadline (and not yet past
    /// the deadline), plus each catch-up this plan kept. A catch-up the 64 limit left out is not remembered, so it
    /// is not taken for one that went off.
    static func remembered(
        _ earlier: [ReminderIdentity: CatchUp], tasks: [ReminderTask], kept: [DeadlineReminder],
        context: CatchUpContext
    ) -> [ReminderIdentity: CatchUp] {
        var deadlines: [ReminderIdentity: CalendarDate] = [:]
        for item in tasks where !item.task.isDone {
            if let deadline = item.task.deadline {
                deadlines[ReminderIdentity(workspaceID: item.workspaceID, taskID: item.task.id)] = deadline
            }
        }
        var result = earlier.filter { identity, catchUp in
            deadlines[identity] == catchUp.deadline && catchUp.deadline >= context.today
        }
        for reminder in kept where reminder.kind == .ahead {
            let identity = ReminderIdentity(workspaceID: reminder.workspaceID, taskID: reminder.taskID)
            guard let deadline = deadlines[identity],
                  reminder.day != deadline.adding(days: -context.leadDays) else { continue }
            result[identity] = CatchUp(day: reminder.day, deadline: deadline)
        }
        return result
    }
}
