@testable import BrievieCore
import Foundation
import Synchronization
import Testing

/// Reminders follow the task list: scheduled at each refresh, and removed when a task is done, a deadline moves,
/// a workspace is left or reminders are switched off.
@Suite struct DeadlineRemindersTests {
    private static let amsterdam = TimeZone(identifier: "Europe/Amsterdam") ?? .gmt
    /// 2026-11-19 12:00 in Amsterdam.
    private static let now = Date(timeIntervalSince1970: 1_795_086_000)

    private let home = UUID()
    private let business = UUID()
    private let center = InMemoryReminderCenter()
    private let settings = InMemoryReminderSettings()
    private let tasks = TaskList()

    private func reminders() -> DeadlineReminders {
        DeadlineReminders(
            center: center, settings: settings, tasks: { [tasks] in try await tasks.open(in: $0) }, now: { Self.now },
            timeZone: { Self.amsterdam }
        )
    }

    private static func task(day: Int, id: UUID = UUID(), sender: String = "CAK") -> WorkspaceTask {
        WorkspaceTask(
            id: id, type: "pay", description: "Betaal € 80", deadline: CalendarDate(year: 2026, month: 12, day: day),
            isDone: false, documentID: UUID(), sender: sender
        )
    }

    private var pendingTasks: Set<UUID> {
        Set(center.pending.values.map(\.taskID))
    }

    @Test func offByDefaultNothingIsScheduled() async {
        tasks.set(home, [Self.task(day: 10)])

        await reminders().reschedule(workspaces: [home])

        #expect(center.pending.isEmpty)
        #expect(center.permissionRequests == 0)
    }

    @Test func onEveryOpenTaskOfEveryWorkspaceGetsItsReminders() async {
        settings.setEnabled(true)
        let mine = Self.task(day: 10)
        let theirs = Self.task(day: 12)
        tasks.set(home, [mine])
        tasks.set(business, [theirs])

        await reminders().reschedule(workspaces: [home, business])

        #expect(center.pending.count == 4)
        #expect(pendingTasks == [mine.id, theirs.id])
        #expect(Set(center.pending.values.map(\.workspaceID)) == [home, business])
    }

    @Test func aCompletedTaskLosesItsReminders() async {
        settings.setEnabled(true)
        let done = Self.task(day: 10)
        let open = Self.task(day: 12)
        tasks.set(home, [done, open])
        let reminders = reminders()
        await reminders.reschedule(workspaces: [home])

        tasks.set(home, [open])
        await reminders.reschedule()

        #expect(pendingTasks == [open.id])
    }

    @Test func aMovedDeadlineMovesItsReminders() async {
        settings.setEnabled(true)
        let id = UUID()
        tasks.set(home, [Self.task(day: 10, id: id)])
        let reminders = reminders()
        await reminders.reschedule(workspaces: [home])

        tasks.set(home, [Self.task(day: 20, id: id)])
        await reminders.reschedule()

        #expect(center.pending.count == 2)
        #expect(Set(center.pending.values.map(\.day)) == [
            CalendarDate(year: 2026, month: 12, day: 17), CalendarDate(year: 2026, month: 12, day: 20)
        ])
    }

    @Test func aWorkspaceThatIsLeftLosesItsReminders() async {
        settings.setEnabled(true)
        tasks.set(home, [Self.task(day: 10)])
        tasks.set(business, [Self.task(day: 12)])
        let reminders = reminders()
        await reminders.reschedule(workspaces: [home, business])

        await reminders.reschedule(workspaces: [home])

        #expect(Set(center.pending.values.map(\.workspaceID)) == [home])
    }

    @Test func switchingOffRemovesPendingAndDeliveredReminders() async {
        settings.setEnabled(true)
        let task = Self.task(day: 10)
        tasks.set(home, [task])
        let reminders = reminders()
        await reminders.reschedule(workspaces: [home])
        let ahead = ReminderPlanner.identifier(workspace: home, task: task.id, kind: .ahead)
        center.deliver(ahead)

        settings.setEnabled(false)
        await reminders.removeAll()

        #expect(center.pending.isEmpty)
        #expect(center.delivered.isEmpty)
        // And a later refresh adds nothing while it is off.
        await reminders.reschedule()
        #expect(center.pending.isEmpty)
    }

    @Test func forgettingThePairingRemovesEverythingAndKnowsNoWorkspace() async {
        settings.setEnabled(true)
        tasks.set(home, [Self.task(day: 10)])
        let reminders = reminders()
        await reminders.reschedule(workspaces: [home])

        await reminders.forget()

        #expect(center.pending.isEmpty)
        #expect(!settings.isEnabled())
        // Switched on again before the workspaces loaded: nothing of the old pairing comes back.
        settings.setEnabled(true)
        await reminders.reschedule()
        #expect(center.pending.isEmpty)
    }

    @Test func beforeTheFirstLoadOfAProcessTheRemindersOfAnEarlierRunStay() async {
        settings.setEnabled(true)
        tasks.set(home, [Self.task(day: 10)])
        await reminders().reschedule(workspaces: [home])

        // The app was ended and started again: a refresh before the workspaces loaded knows no workspace yet.
        await reminders().reschedule()

        #expect(center.pending.count == 2)
    }

    @Test func aWorkspaceThatCouldNotBeReadKeepsItsReminders() async {
        settings.setEnabled(true)
        let mine = Self.task(day: 10)
        let theirs = Self.task(day: 12)
        tasks.set(home, [mine])
        tasks.set(business, [theirs])
        let reminders = reminders()
        await reminders.reschedule(workspaces: [home, business])

        tasks.fail(business)
        tasks.set(home, [])
        await reminders.reschedule()

        #expect(pendingTasks == [theirs.id])
    }

    @Test func remindersKeptForAnUnreadableWorkspaceCountTowardsTheLimit() async {
        settings.setEnabled(true)
        tasks.set(business, (1...20).map { Self.task(day: $0 + 1) })
        let reminders = reminders()
        await reminders.reschedule(workspaces: [business])
        #expect(center.pending.count == 40)

        tasks.fail(business)
        tasks.set(home, (1...20).map { Self.task(day: $0 + 1) })
        await reminders.reschedule(workspaces: [home, business])

        #expect(center.pending.count == ReminderPlanner.maxPending)
        #expect(center.pending.values.count { $0.workspaceID == business } == 40)
    }

    @Test func withoutPermissionNothingIsScheduled() async {
        settings.setEnabled(true)
        center.setPermission(.denied)
        tasks.set(home, [Self.task(day: 10)])

        await reminders().reschedule(workspaces: [home])

        #expect(center.pending.isEmpty)
    }

    @Test func aDeliveredReminderGoesWhenItsTaskIsDoneAndStaysWhileOpen() async {
        settings.setEnabled(true)
        let done = Self.task(day: 10)
        let open = Self.task(day: 12)
        tasks.set(home, [done, open])
        let reminders = reminders()
        await reminders.reschedule(workspaces: [home])
        let doneAhead = ReminderPlanner.identifier(workspace: home, task: done.id, kind: .ahead)
        let openAhead = ReminderPlanner.identifier(workspace: home, task: open.id, kind: .ahead)
        center.deliver(doneAhead)
        center.deliver(openAhead)

        tasks.set(home, [open])
        await reminders.reschedule()

        #expect(center.delivered == [openAhead])
    }

    @Test func anotherNotificationOfTheAppIsNeverTouched() async {
        settings.setEnabled(true)
        center.addForeign("something.else")
        let reminders = reminders()

        await reminders.reschedule(workspaces: [home])
        await reminders.removeAll()

        #expect(center.delivered == ["something.else"])
    }

    @Test func theSettingsDecideLeadTimeAndSender() async {
        settings.setEnabled(true)
        settings.setLeadDays(7)
        settings.setShowsSender(true)
        tasks.set(home, [Self.task(day: 20, sender: "Gemeente")])

        await reminders().reschedule(workspaces: [home])

        let bodies = center.pending.values.sorted { $0.fireDate < $1.fireDate }.map(\.body)
        #expect(bodies == [
            "Een termijn van Gemeente loopt over 7 dagen af.", "Een termijn van Gemeente loopt vandaag af."
        ])
    }

    @Test func aRemovalAskedForDuringARefreshWins() async {
        settings.setEnabled(true)
        tasks.set(home, [Self.task(day: 10)])
        tasks.hold()
        let reminders = reminders()

        let refresh = Task { await reminders.reschedule(workspaces: [home]) }
        while !tasks.isWaiting { await Task.yield() }
        settings.setEnabled(false)
        let removal = Task { await reminders.removeAll() }
        tasks.release()
        await refresh.value
        await removal.value

        #expect(center.pending.isEmpty)
    }
}

/// A catch-up survives the end of the process: it is remembered in the settings, so it comes once.
@Suite struct DeadlineReminderCatchUpTests {
    private let center = InMemoryReminderCenter()
    private let settings = InMemoryReminderSettings()
    private let clock = TestClock()
    private let home = UUID()

    @Test func aCatchUpIsNotMadeAgainTheNextDay() async {
        settings.setEnabled(true)
        settings.setLeadDays(7)
        let task = WorkspaceTask(
            id: UUID(), type: "pay", description: "", deadline: CalendarDate(year: 2026, month: 11, day: 25),
            isDone: false, documentID: nil, sender: ""
        )
        let make = { [center, settings, clock] in
            DeadlineReminders(
                center: center, settings: settings, tasks: { _ in [task] }, now: { clock.now },
                timeZone: { TimeZone(identifier: "Europe/Amsterdam") ?? .gmt }
            )
        }
        // 2026-11-19 20:00 in Amsterdam: seven days ahead (the 18th) has passed, so the 20th at nine.
        clock.now = Date(timeIntervalSince1970: 1_795_114_800)
        await make().reschedule(workspaces: [home])
        #expect(center.pending.values.map(\.day.day).sorted() == [20, 25])

        // It went off; the next day a new process refreshes: no second catch-up.
        center.deliver(ReminderPlanner.identifier(workspace: home, task: task.id, kind: .ahead))
        clock.now = clock.now.addingTimeInterval(86_400)
        await make().reschedule(workspaces: [home])
        #expect(center.pending.values.map(\.day.day) == [25])
    }
}

private final class TestClock: Sendable {
    private let value = Mutex(Date.distantPast)
    var now: Date {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}

/// The open tasks per workspace the server would answer; a workspace can fail, and a read can be held.
private final class TaskList: Sendable {
    private struct State {
        var tasks: [UUID: [WorkspaceTask]] = [:]
        var failing: Set<UUID> = []
        var held = false
        var waiting = false
    }

    private let state = Mutex(State())

    var isWaiting: Bool { state.withLock { $0.waiting } }

    func set(_ workspace: UUID, _ tasks: [WorkspaceTask]) {
        state.withLock { $0.tasks[workspace] = tasks }
    }

    func fail(_ workspace: UUID) {
        _ = state.withLock { $0.failing.insert(workspace) }
    }

    func hold() {
        state.withLock { $0.held = true }
    }

    func release() {
        state.withLock { $0.held = false }
    }

    func open(in workspace: UUID) async throws -> [WorkspaceTask] {
        state.withLock { $0.waiting = $0.held }
        while state.withLock({ $0.held }) { await Task.yield() }
        state.withLock { $0.waiting = false }
        return try state.withLock { state in
            if state.failing.contains(workspace) { throw DocumentsError.unreachable }
            return state.tasks[workspace] ?? []
        }
    }
}
