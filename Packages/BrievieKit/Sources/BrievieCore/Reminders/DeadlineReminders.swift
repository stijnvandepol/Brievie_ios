import Foundation
import OSLog

/// Local notifications for the deadlines of open tasks, made by the app itself: nothing goes to a server and no
/// push service is involved.
///
/// They only know what the app last read: every refresh (the workspaces loading, a confirm, a ticked task) reads
/// the open tasks of each workspace again and brings the pending reminders in line (`ReminderPlanner`). There is no
/// background fetch, so a deadline added elsewhere gets its reminders the next time the app opens. Work runs one
/// call at a time, in the order the calls came: a removal asked for during a refresh runs after it, so it wins.
public actor DeadlineReminders {
    public typealias TaskSource = @Sendable (UUID) async throws -> [WorkspaceTask]

    private static let logger = Logger(subsystem: "nl.stijnvdpol.brievie", category: "reminders")

    /// Read and written by the settings screen; cleared with the pairing.
    public nonisolated let settings: any ReminderSettings
    private let center: any ReminderCenter
    private let tasks: TaskSource
    private let now: @Sendable () -> Date
    private let timeZone: @Sendable () -> TimeZone
    /// The workspaces of the last workspaces load: a refresh after a confirm uses them. `nil` until the first load
    /// in this process: the reminders pending from an earlier run then stay as they are.
    private var workspaces: [UUID]?
    /// The last call queued; the next one waits for it.
    private var last: Task<Void, Never>?

    /// - Parameters:
    ///   - tasks: the open tasks of a workspace on the server.
    ///   - now: the clock; `timeZone`: the phone's time zone (both injected so tests are fixed).
    public init(
        center: any ReminderCenter,
        settings: any ReminderSettings,
        tasks: @escaping TaskSource,
        now: @escaping @Sendable () -> Date = { Date() },
        timeZone: @escaping @Sendable () -> TimeZone = { .current }
    ) {
        self.center = center
        self.settings = settings
        self.tasks = tasks
        self.now = now
        self.timeZone = timeZone
    }

    public func permission() async -> NotificationPermission {
        await center.permission()
    }

    /// Shows the system's question when it was never asked; `true` when notifications are allowed.
    public func requestPermission() async -> Bool {
        switch await center.permission() {
        case .allowed: true
        case .denied: false
        case .notDetermined: await center.requestPermission()
        }
    }

    /// After the workspaces loaded: these are the workspaces this phone is paired to now.
    public func reschedule(workspaces: [UUID]) async {
        await serially { reminders in
            reminders.workspaces = workspaces
            await reminders.performReschedule()
        }
    }

    /// After a confirm, a ticked task or a changed setting: the workspaces of the last load.
    public func reschedule() async {
        await serially { await $0.performReschedule() }
    }

    /// Reminders were switched off: every pending and delivered reminder goes.
    public func removeAll() async {
        await serially { await $0.performRemoveAll() }
    }

    /// The pairing is forgotten (unpaired or revoked): the settings go back to off, no workspace is known any more,
    /// and every reminder goes.
    public func forget() async {
        settings.removeAll()
        await serially { reminders in
            reminders.workspaces = []
            await reminders.performRemoveAll()
        }
    }

    private func serially(_ work: @escaping @Sendable (isolated DeadlineReminders) async -> Void) async {
        let previous = last
        let job = Task {
            await previous?.value
            await work(self)
        }
        last = job
        await job.value
    }

    private func performReschedule() async {
        guard settings.isEnabled() else {
            await performRemoveAll()
            return
        }
        guard await center.permission() == .allowed else {
            await center.removePending(ours(await center.pendingIdentifiers()).map(\.identifier))
            return
        }
        guard let workspaces else { return }
        var open: [ReminderTask] = []
        var unreadable: Set<UUID> = []
        for workspace in workspaces {
            do {
                open += try await tasks(workspace).map { ReminderTask(workspaceID: workspace, task: $0) }
            } catch {
                // Keep what is pending for it: an unreachable server does not mean the deadlines are gone.
                unreadable.insert(workspace)
                Self.logger.info("Reminders kept for a workspace that could not be read")
            }
        }
        // Switched off while the tasks were read: the removal is queued after this call, but add nothing.
        guard settings.isEnabled() else { return }
        let pending = ours(await center.pendingIdentifiers())
        let kept = pending.filter { unreadable.contains($0.identity.workspaceID) }
        let plan = ReminderPlanner.plan(
            open, now: now(), timeZone: timeZone(), leadDays: settings.leadDays(), showsSender: settings.showsSender(),
            limit: ReminderPlanner.maxPending - kept.count
        )
        let planned = Set(plan.map(\.identifier))
        let stale = pending.filter { !planned.contains($0.identifier) && !unreadable.contains($0.identity.workspaceID) }
        await center.removePending(stale.map(\.identifier))
        await center.schedule(plan)
        // A reminder already shown for a task that is done, or of a workspace that is gone, leaves Notification
        // Centre too; one for a task that is still open stays.
        let openTasks = Set(open.map { ReminderIdentity(workspaceID: $0.workspaceID, taskID: $0.task.id) })
        let delivered = ours(await center.deliveredIdentifiers()).filter { reminder in
            !unreadable.contains(reminder.identity.workspaceID) && !openTasks.contains(reminder.identity)
        }
        await center.removeDelivered(delivered.map(\.identifier))
    }

    private func performRemoveAll() async {
        await center.removePending(ours(await center.pendingIdentifiers()).map(\.identifier))
        await center.removeDelivered(ours(await center.deliveredIdentifiers()).map(\.identifier))
    }

    /// Brievie's reminders among the app's notifications; anything else is left alone.
    private func ours(_ identifiers: [String]) -> [(identifier: String, identity: ReminderIdentity)] {
        identifiers.compactMap { identifier in ReminderPlanner.parse(identifier).map { (identifier, $0) } }
    }
}
