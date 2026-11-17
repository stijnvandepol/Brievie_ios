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
    /// - Parameter consentedSourceID: the account the user said yes to after `.needsConsent`; only that one.
    public func enable(workspace: UUID, consentedSourceID: String? = nil) async -> CalendarSyncResult {
        await exclusively(workspace) { sync in
            // An unpair while this runs clears the settings: then nothing may be stored afterwards.
            let generation = sync.settings.clearGeneration()
            let open = await sync.openTasks(workspace)
            if case .failure(let error) = open, error as? DocumentsError == .notSupported { return .tasksNotSupported }
            guard await sync.requestAccessIfNeeded() else { return .noAccess }
            switch await sync.makeCalendar(workspace, generation: generation, consentedSourceID: consentedSourceID) {
            case .made: return await sync.performSync(workspace, open: open)
            case .notWanted: return .off
            case .needsConsent(let source): return .needsConsent(source)
            case .noAccount: return .noCalendarAccount
            case .failed: return .failed
            }
        }
    }

    /// The account the workspace's calendar is in, for the footer under its switch; `nil` while it is off or the
    /// account is not known (any more).
    public func destination(workspace: UUID) async -> CalendarSource? {
        guard settings.isEnabled(for: workspace), let id = settings.sourceID(for: workspace) else { return nil }
        return await store.sources().source(id: id)
    }

    /// Turns the switch off; with `removeCalendar`, also deletes the workspace's calendar (nothing else), or only
    /// its own events when the calendar also holds events of the user. `nil` when nothing was removed (not asked,
    /// no calendar, or it failed).
    /// - Parameter generation: the settings' clear generation the caller saw; when the settings were cleared
    ///   since (an unpair, perhaps followed by pairing again), nothing is touched: the calendar now stored may be
    ///   a new one.
    @discardableResult
    public func disable(workspace: UUID, removeCalendar: Bool, ifGeneration generation: Int? = nil) async
        -> CalendarRemoval? {
        await exclusively(workspace) { sync in
            if let generation, sync.settings.clearGeneration() != generation { return nil }
            return await sync.performDisable(workspace, removeCalendar: removeCalendar)
        }
    }

    /// Removes the calendars marked for removal after a revocation (`CalendarSettings.pendingRemovals()`),
    /// without asking: a revoked phone may be a stolen one. A calendar that also holds events of the user stays;
    /// only Brievie's events go (`CalendarStore.removeCalendar(id:)`). A calendar stays marked until that
    /// succeeded with access, so the next activation tries again; one a new pairing took over meanwhile is left
    /// alone and unmarked.
    public func removePendingRemovals() async {
        for (calendarID, workspace) in settings.pendingRemovals() {
            await exclusively(workspace) { sync in
                guard sync.settings.pendingRemovals()[calendarID] != nil else { return }
                if sync.settings.calendarIDs().values.contains(calendarID) {
                    sync.settings.removalDone(calendarID: calendarID)
                    return
                }
                do {
                    _ = try await sync.store.removeCalendar(id: calendarID)
                    sync.settings.removalDone(calendarID: calendarID)
                } catch {
                    Self.logger.error(
                        "Could not remove a calendar after revocation: \(String(describing: error), privacy: .private)"
                    )
                }
            }
        }
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
        /// Only another account is left, and the user has not said yes to it.
        case needsConsent(CalendarSource)
        case noAccount
        case failed
    }

    private func makeCalendar(_ workspace: UUID, generation: Int, consentedSourceID: String?) async -> MadeCalendar {
        let name = workspaceName(workspace)
        guard !name.isEmpty else { return .failed }
        return await choosingCalendar { sync in
            guard sync.settings.clearGeneration() == generation else { return .notWanted }
            let sourceID: String
            switch await CalendarSourceChoice(sync.store.sources()) {
            case .silent(let source):
                sourceID = source.id
            case .needsConsent(let source):
                guard consentedSourceID == source.id else { return .needsConsent(source) }
                sourceID = source.id
            case .none:
                return .noAccount
            }
            do {
                let calendar = try await sync.store.ensureCalendar(
                    named: Self.calendarName(workspaceName: name),
                    existingID: sync.settings.calendarID(for: workspace),
                    excluding: sync.calendarsOfOtherWorkspaces(workspace),
                    window: CalendarSyncPlanner.window(today: sync.today()),
                    sourceID: sourceID
                )
                guard sync.settings.enable(
                    workspace: workspace, calendarID: calendar.id, sourceID: calendar.sourceID, ifGeneration: generation
                ) else {
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
            let tasks = try await tasks(workspace)
            // Read after the tasks: a choice made while they loaded counts.
            let showsDetails = settings.showsDetails(for: workspace)
            return .success(tasks.compactMap { task in
                CalendarTask.from(task, typeTitle: typeTitle, showsDetails: showsDetails)
            })
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
        } catch let error as CalendarStoreError where error.reason == .sourceGone {
            return .sourceGone
        } catch {
            Self.logger.error("Calendar sync failed: \(String(describing: error), privacy: .private)")
            return .failed
        }
    }

    /// The calendar this sync writes in: the stored one, or one found or made again in the account it was in
    /// (never another). `nil` when the setting was cleared meanwhile (unpairing or the switch): it is never written
    /// back. When that account is gone, the switch goes off and this fails with `.sourceGone`.
    private func chooseCalendar(
        _ workspace: UUID, named name: String, storedID: String, window: ClosedRange<CalendarDate>
    ) async -> Result<String?, any Error> {
        let generation = settings.clearGeneration()
        guard settings.calendarID(for: workspace) == storedID else { return .success(nil) }
        do {
            let calendar = try await store.ensureCalendar(
                named: Self.calendarName(workspaceName: name), existingID: storedID,
                excluding: calendarsOfOtherWorkspaces(workspace), window: window,
                sourceID: await agreedSource(workspace)
            )
            guard settings.calendarID(for: workspace) == storedID else { return .success(nil) }
            if calendar.id != storedID || calendar.sourceID != settings.sourceID(for: workspace),
               !settings.enable(
                   workspace: workspace, calendarID: calendar.id, sourceID: calendar.sourceID, ifGeneration: generation
               ) {
                return .success(nil)
            }
            return .success(calendar.id)
        } catch let error as CalendarStoreError where error.reason == .sourceGone {
            if settings.calendarID(for: workspace) == storedID { settings.disable(workspace: workspace) }
            return .failure(error)
        } catch {
            return .failure(error)
        }
    }

    /// The account the workspace's calendar may be made again in: the one stored with it. A setting from before
    /// the account was stored never had the user's yes for another account, so it may only use iCloud or the
    /// phone.
    private func agreedSource(_ workspace: UUID) async -> String? {
        if let stored = settings.sourceID(for: workspace) { return stored }
        if case .silent(let source) = await CalendarSourceChoice(store.sources()) { return source.id }
        return nil
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
