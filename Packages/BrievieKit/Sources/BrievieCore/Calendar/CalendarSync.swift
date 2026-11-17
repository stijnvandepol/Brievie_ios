import Foundation
import OSLog

/// Puts the open tasks with a deadline of a workspace in that workspace's own calendar on the phone.
///
/// The calendar is the state: every sync reads the open tasks and the calendar's events in the window and
/// applies what `CalendarSyncPlanner` returns. It writes only in the calendar it made for the workspace, and
/// only while the switch is on. Work for one workspace never runs twice at the same time: a call waits for the
/// one that is running and then runs itself.
public actor CalendarSync {
    public typealias TaskSource = @Sendable (UUID) async throws -> [WorkspaceTask]

    private static let logger = Logger(subsystem: "nl.stijnvdpol.brievie", category: "calendar")

    private let store: any CalendarStore
    private let settings: any CalendarSettings
    private let tasks: TaskSource
    private let workspaceName: @Sendable (UUID) -> String
    private let typeTitle: @Sendable (String) -> String
    private let today: @Sendable () -> CalendarDate
    /// The work running per workspace. Its task ends after it took itself out of here, so a caller that waited
    /// for it finds the place free (or taken by a caller that came first).
    private var running: [UUID: (token: UUID, done: Task<Void, Never>)] = [:]
    /// The last calendar choice queued, for all workspaces together: reading the other workspaces' calendars,
    /// choosing or making one and storing it is one step, so two workspaces with the same name never take the
    /// same calendar.
    private var choosing: Task<Void, Never>?

    /// - Parameters:
    ///   - tasks: the open tasks of a workspace on the server.
    ///   - workspaceName: names the calendar "Brievie – <werkruimte>".
    ///   - typeTitle: the Dutch name of a task type code, for the event's title.
    ///   - today: the day on this phone, for the window.
    public init(
        store: any CalendarStore,
        settings: any CalendarSettings,
        tasks: @escaping TaskSource,
        workspaceName: @escaping @Sendable (UUID) -> String,
        typeTitle: @escaping @Sendable (String) -> String,
        today: @escaping @Sendable () -> CalendarDate
    ) {
        self.store = store
        self.settings = settings
        self.tasks = tasks
        self.workspaceName = workspaceName
        self.typeTitle = typeTitle
        self.today = today
    }

    /// "Brievie – <werkruimte>".
    public static func calendarName(workspaceName: String) -> String {
        String(format: AppStrings.calendarNameFormat, workspaceName)
    }

    /// Brings the workspace's calendar in line with its open tasks. Does nothing while the switch is off or
    /// without calendar access; makes the calendar again when the user deleted it.
    public func sync(workspace: UUID) async -> CalendarSyncResult {
        await exclusively(workspace) { await $0.performSync(workspace, open: nil) }
    }

    /// Whether Brievie may use the calendars now; the switch shows a message when access was taken away.
    public func access() async -> CalendarAccess {
        await store.access()
    }

    /// Turns the switch on: asks for access when needed, makes (or finds) the calendar, remembers it and syncs.
    /// The open tasks are read first, before the access prompt: a server without a task list gets no prompt and
    /// no calendar. Any other failure to read them still makes the calendar; the next sync fills it.
    public func enable(workspace: UUID) async -> CalendarSyncResult {
        await exclusively(workspace) { sync in
            // An unpair while this runs clears the settings: then nothing may be stored afterwards.
            let generation = sync.settings.clearGeneration()
            let open = await sync.openTasks(workspace)
            if case .failure(let error) = open, error as? DocumentsError == .notSupported { return .tasksNotSupported }
            guard await sync.requestAccessIfNeeded() else { return .noAccess }
            switch await sync.makeCalendar(workspace, generation: generation) {
            case .made: return await sync.performSync(workspace, open: open)
            case .notWanted: return .off
            case .failed: return .failed
            }
        }
    }

    /// Turns the switch off; with `removeCalendar`, also deletes the workspace's calendar (nothing else), or only
    /// its own events when the calendar also holds events of the user. `nil` when nothing was removed (not asked,
    /// no calendar, or it failed).
    @discardableResult
    public func disable(workspace: UUID, removeCalendar: Bool) async -> CalendarRemoval? {
        await exclusively(workspace) { await $0.performDisable(workspace, removeCalendar: removeCalendar) }
    }

    private func exclusively<Result: Sendable>(
        _ workspace: UUID, _ work: @escaping @Sendable (isolated CalendarSync) async -> Result
    ) async -> Result {
        while let current = running[workspace] {
            await current.done.value
        }
        let token = UUID()
        let job = Task { await work(self) }
        running[workspace] = (token, Task {
            _ = await job.value
            self.finish(workspace, token: token)
        })
        return await job.value
    }

    private func finish(_ workspace: UUID, token: UUID) {
        if running[workspace]?.token == token { running[workspace] = nil }
    }

    /// Runs `work` after every calendar choice queued before it, for all workspaces.
    private func choosingCalendar<Result: Sendable>(
        _ work: @escaping @Sendable (isolated CalendarSync) async -> Result
    ) async -> Result {
        let previous = choosing
        let job = Task {
            await previous?.value
            return await work(self)
        }
        choosing = Task { _ = await job.value }
        return await job.value
    }

    private func requestAccessIfNeeded() async -> Bool {
        if await store.access() == .granted { return true }
        return await store.requestAccess() == .granted
    }

    private enum MadeCalendar {
        case made
        /// The settings were cleared (unpaired) since `generation`: nothing was stored.
        case notWanted
        case failed
    }

    private func makeCalendar(_ workspace: UUID, generation: Int) async -> MadeCalendar {
        let name = workspaceName(workspace)
        guard !name.isEmpty else { return .failed }
        return await choosingCalendar { sync in
            guard sync.settings.clearGeneration() == generation else { return .notWanted }
            do {
                let id = try await sync.store.ensureCalendar(
                    named: Self.calendarName(workspaceName: name),
                    existingID: sync.settings.calendarID(for: workspace),
                    excluding: sync.calendarsOfOtherWorkspaces(workspace),
                    window: CalendarSyncPlanner.window(today: sync.today())
                )
                guard sync.settings.enable(workspace: workspace, calendarID: id, ifGeneration: generation) else {
                    return .notWanted
                }
                return .made
            } catch {
                Self.logger.error("Could not make the calendar: \(String(describing: error), privacy: .private)")
                return .failed
            }
        }
    }

    /// The open tasks of the workspace as calendar events-to-be.
    private func openTasks(_ workspace: UUID) async -> Result<[CalendarTask], any Error> {
        do {
            return .success(try await tasks(workspace).compactMap { CalendarTask.from($0, typeTitle: typeTitle) })
        } catch {
            return .failure(error)
        }
    }

    /// - Parameter open: the open tasks when the caller read them already; `nil` reads them here.
    private func performSync(_ workspace: UUID, open: Result<[CalendarTask], any Error>?) async -> CalendarSyncResult {
        guard let storedID = settings.calendarID(for: workspace) else { return .off }
        guard await store.access() == .granted else { return .noAccess }
        // Without the workspace's name no calendar is made: it would be called "Brievie – ".
        let name = workspaceName(workspace)
        guard !name.isEmpty else { return .failed }
        do {
            let fetched = if let open { open } else { await openTasks(workspace) }
            let open = try fetched.get()
            let window = CalendarSyncPlanner.window(today: today())
            let chosen = await choosingCalendar { sync in
                await sync.chooseCalendar(workspace, named: name, storedID: storedID, window: window)
            }
            guard let calendarID = try chosen.get() else { return .off }
            let events = try await store.events(calendarID: calendarID, window: window)
            let changes = CalendarSyncPlanner.plan(tasks: open, events: events, window: window)
            if !changes.isEmpty { try await store.apply(changes, calendarID: calendarID) }
            return Self.counted(changes)
        } catch DocumentsError.notSupported {
            return .tasksNotSupported
        } catch {
            Self.logger.error("Calendar sync failed: \(String(describing: error), privacy: .private)")
            return .failed
        }
    }

    /// The calendar this sync writes in: the stored one, or one found or made again. `nil` when the setting was
    /// cleared meanwhile (unpairing or the switch): it is never written back.
    private func chooseCalendar(
        _ workspace: UUID, named name: String, storedID: String, window: ClosedRange<CalendarDate>
    ) async -> Result<String?, any Error> {
        let generation = settings.clearGeneration()
        guard settings.calendarID(for: workspace) == storedID else { return .success(nil) }
        do {
            let calendarID = try await store.ensureCalendar(
                named: Self.calendarName(workspaceName: name), existingID: storedID,
                excluding: calendarsOfOtherWorkspaces(workspace), window: window
            )
            guard settings.calendarID(for: workspace) == storedID else { return .success(nil) }
            if calendarID != storedID,
               !settings.enable(workspace: workspace, calendarID: calendarID, ifGeneration: generation) {
                return .success(nil)
            }
            return .success(calendarID)
        } catch {
            return .failure(error)
        }
    }

    private func calendarsOfOtherWorkspaces(_ workspace: UUID) -> Set<String> {
        Set(settings.calendarIDs().filter { $0.key != workspace }.values)
    }

    private func performDisable(_ workspace: UUID, removeCalendar: Bool) async -> CalendarRemoval? {
        let calendarID = settings.calendarID(for: workspace)
        settings.disable(workspace: workspace)
        guard removeCalendar, let calendarID else { return nil }
        do {
            return try await store.removeCalendar(id: calendarID)
        } catch {
            Self.logger.error("Could not remove the calendar: \(String(describing: error), privacy: .private)")
            return nil
        }
    }

    private static func counted(_ changes: [CalendarChange]) -> CalendarSyncResult {
        var created = 0
        var updated = 0
        var deleted = 0
        for change in changes {
            switch change {
            case .create: created += 1
            case .update: updated += 1
            case .delete: deleted += 1
            }
        }
        return .done(created: created, updated: updated, deleted: deleted)
    }
}
