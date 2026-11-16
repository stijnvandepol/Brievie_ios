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
    /// calendar should go too.
    public func toggle(_ wantsOn: Bool) {
        if wantsOn {
            guard !isOn else { return }
            isOn = true
            message = nil
            showsOpenSettings = false
            let sync = sync
            let workspace = workspaceID
            pendingTask = Task {
                show(await sync.enable(workspace: workspace))
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
        pendingTask = Task {
            await previous?.value
            await sync.disable(workspace: workspace, removeCalendar: removeCalendar)
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
