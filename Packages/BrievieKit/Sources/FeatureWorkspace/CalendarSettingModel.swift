import BrievieCore
import Foundation
import Observation

/// What the Workspaces screen needs for the calendar switches. The app supplies it; without it there are none.
public struct WorkspaceCalendar {
    let sync: CalendarSync
    let settings: any CalendarSettings
    let openSettings: @MainActor () -> Void
    /// Called with the rows after every successful load: the app learns the workspaces' names and syncs.
    let didLoad: @MainActor ([WorkspacesModel.Row]) -> Void

    public init(
        sync: CalendarSync,
        settings: any CalendarSettings,
        openSettings: @escaping @MainActor () -> Void,
        didLoad: @escaping @MainActor ([WorkspacesModel.Row]) -> Void
    ) {
        self.sync = sync
        self.settings = settings
        self.openSettings = openSettings
        self.didLoad = didLoad
    }
}

/// The "Zet deadlines in mijn agenda" switch of one workspace.
@MainActor
@Observable
public final class CalendarSettingModel {
    public let workspaceID: UUID
    public let workspaceName: String
    public private(set) var isOn: Bool
    /// What the switch puts where, under it: "Je taken met een deadline komen in een eigen agenda 'Brievie – …'".
    public var footer: String {
        String(format: WorkspaceStrings.calendarFooterFormat, CalendarSync.calendarName(workspaceName: workspaceName))
    }

    /// Why the switch went back off; `nil` when there is nothing to say.
    public private(set) var message: String?
    /// The message is about refused access: offer "Open Instellingen".
    public private(set) var showsOpenSettings = false
    /// The "ook verwijderen?" question is on screen. Answering it turns the switch off; dismissing it keeps it on.
    public var isAskingToRemove = false

    /// "Agenda 'Brievie – <naam>' ook verwijderen?"
    public var removeQuestion: String {
        String(
            format: WorkspaceStrings.calendarRemoveQuestionFormat,
            CalendarSync.calendarName(workspaceName: workspaceName)
        )
    }

    private let sync: CalendarSync
    private let settings: any CalendarSettings
    private let openSystemSettings: @MainActor () -> Void
    /// The work started by the switch; owned by the model so that leaving the screen does not cancel it. Tests
    /// await it.
    @ObservationIgnored private(set) var pendingTask: Task<Void, Never>?
    /// Counts the switch's actions: only the result of the latest one may change what the switch shows.
    @ObservationIgnored private var generation = 0
    /// The access check started by `refreshAccess()`. Tests await it.
    @ObservationIgnored private(set) var accessTask: Task<Void, Never>?

    public init(
        workspaceID: UUID,
        workspaceName: String,
        sync: CalendarSync,
        settings: any CalendarSettings,
        openSettings: @escaping @MainActor () -> Void
    ) {
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
        self.sync = sync
        self.settings = settings
        openSystemSettings = openSettings
        isOn = settings.isEnabled(for: workspaceID)
    }

    /// The switch was flipped. On: asks for access, makes the calendar and fills it. Off: asks first whether the
    /// calendar should go too. Work for the switch runs in the order of the flips.
    public func toggle(_ wantsOn: Bool) {
        if wantsOn {
            guard !isOn else { return }
            isOn = true
            message = nil
            showsOpenSettings = false
            let sync = sync
            let workspace = workspaceID
            let previous = pendingTask
            generation += 1
            let action = generation
            pendingTask = Task {
                await previous?.value
                let result = await sync.enable(workspace: workspace)
                // A later flip decides what the switch shows; this result is old news.
                if action == generation { show(result) }
            }
        } else if isOn {
            isAskingToRemove = true
        }
    }

    /// The answer to "ook verwijderen?": "Verwijderen" (`true`) or "Laten staan" (`false`).
    public func switchOff(removeCalendar: Bool) {
        isAskingToRemove = false
        guard isOn else { return }
        isOn = false
        message = nil
        showsOpenSettings = false
        let sync = sync
        let workspace = workspaceID
        let previous = pendingTask
        generation += 1
        pendingTask = Task {
            await previous?.value
            await sync.disable(workspace: workspace, removeCalendar: removeCalendar)
        }
    }

    /// The app leaves the foreground: the "ook verwijderen?" question (with the workspace's name) must not stay
    /// above the lock screen. Not answering keeps the switch on.
    public func sceneLeftForeground() {
        isAskingToRemove = false
    }

    /// While the switch is on: says so when calendar access was taken away in Settings, and drops that line once
    /// it is back. The switch stays on either way; syncing resumes by itself when access returns.
    public func refreshAccess() {
        guard isOn else { return }
        let sync = sync
        accessTask = Task {
            let access = await sync.access()
            guard isOn else { return }
            if access == .granted {
                if showsOpenSettings {
                    message = nil
                    showsOpenSettings = false
                }
            } else {
                message = WorkspaceStrings.calendarNoAccess
                showsOpenSettings = true
            }
        }
    }

    /// "Open Instellingen", after access was refused.
    public func openSettings() {
        openSystemSettings()
    }

    private func show(_ result: CalendarSyncResult) {
        switch result {
        case .noAccess:
            isOn = false
            message = WorkspaceStrings.calendarNoAccess
            showsOpenSettings = true
        case .tasksNotSupported:
            isOn = false
            message = WorkspaceStrings.calendarTasksNotSupported
            showsOpenSettings = false
        case .failed:
            // The switch stays on when the calendar exists and only this first fill failed: the next sync retries.
            if !isOn { return }
            isOn = settings.isEnabled(for: workspaceID)
            message = isOn ? nil : WorkspaceStrings.generic
        case .done, .off:
            break
        }
    }
}
