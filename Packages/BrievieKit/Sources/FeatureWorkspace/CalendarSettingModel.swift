import BrievieCore
import Foundation
import Observation

/// What the Workspaces screen needs for the calendar switches. The app supplies it; without it there are none.
public struct WorkspaceCalendar {
    let sync: CalendarSync
    let settings: any CalendarSettings
    let openSettings: @MainActor () -> Void
    /// Called with the rows after every successful load, before the switches sync: the app learns the
    /// workspaces' names.
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
    /// The account the calendar is in, once it is known (`nil` while off).
    public private(set) var destination: CalendarSource?

    /// "Toon de omschrijving in de agenda" (off by default): the events carry the description and the sender.
    public private(set) var showsDetails: Bool

    /// What the switch puts where, under it: the calendar's name, the account it is in, and what the events
    /// show (also on the lock screen).
    public var footer: String {
        let name = CalendarSync.calendarName(workspaceName: workspaceName)
        let place = switch destination?.kind {
        case nil: String(format: WorkspaceStrings.calendarFooterFormat, name)
        case .iCloud: String(format: WorkspaceStrings.calendarFooterICloudFormat, name)
        case .local: String(format: WorkspaceStrings.calendarFooterLocalFormat, name)
        case .other: String(format: WorkspaceStrings.calendarFooterOtherFormat, name, destination?.title ?? "")
        }
        let shown = showsDetails ? WorkspaceStrings.calendarFooterDetailed : WorkspaceStrings.calendarFooterNeutral
        return "\(place) \(shown)"
    }

    /// Under "Toon de omschrijving in de agenda": who can read the text then.
    public var detailsFooter: String { WorkspaceStrings.calendarDetailsFooter }

    /// The switch's VoiceOver hint: every switch has the same label, the footer names this workspace's calendar.
    public var switchHint: String { footer }

    /// Why the switch went back off; `nil` when there is nothing to say.
    public private(set) var message: String?
    /// The message is about refused access: offer "Open Instellingen".
    public private(set) var showsOpenSettings = false
    /// The "ook verwijderen?" question is on screen. Answering it turns the switch off; dismissing it keeps it on.
    public var isAskingToRemove = false
    /// The only account left for the calendar is someone else's: "mag dat?" is on screen. The switch is off until
    /// the user says yes; dismissing it is a no.
    public var isAskingConsent = false
    /// The account the question is about.
    @ObservationIgnored private var consentSource: CalendarSource?

    /// "Brievie zet je taken in de agenda van <account>. Wie die account beheert, kan ze lezen."
    public var consentQuestion: String {
        String(format: WorkspaceStrings.calendarConsentFormat, consentSource?.title ?? "")
    }

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
    /// Switch-ons whose work has not ended: until then the setting is off because it is not stored yet (or will
    /// not be: a question, no account, a failure), not because a sync turned it off.
    @ObservationIgnored private var switchOnsRunning = 0
    /// The access check and sync started by `refresh()`. Tests await it.
    @ObservationIgnored private(set) var refreshTask: Task<Void, Never>?

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
        showsDetails = settings.showsDetails(for: workspaceID)
    }

    /// "Toon de omschrijving in de agenda" was flipped: stored at once, and the events are rewritten by a sync
    /// (one now, after any work the switch still has running).
    public func setShowsDetails(_ shows: Bool) {
        guard shows != showsDetails else { return }
        showsDetails = shows
        settings.setShowsDetails(shows, for: workspaceID)
        guard isOn else { return }
        let sync = sync
        let workspace = workspaceID
        let previous = pendingTask
        pendingTask = Task {
            await previous?.value
            _ = await sync.sync(workspace: workspace)
        }
    }

    /// The switch was flipped. On: asks for access, makes the calendar and fills it. Off: asks first whether the
    /// calendar should go too. Work for the switch runs in the order of the flips.
    public func toggle(_ wantsOn: Bool) {
        if wantsOn {
            guard !isOn else { return }
            switchOn(consentedSourceID: nil)
        } else if isOn {
            isAskingToRemove = true
        }
    }

    /// The answer to "mag dat?": yes makes the calendar in that account (and only there), no leaves the switch off.
    public func answerConsent(_ agrees: Bool) {
        isAskingConsent = false
        guard let source = consentSource else { return }
        consentSource = nil
        guard agrees, !isOn else { return }
        switchOn(consentedSourceID: source.id)
    }

    private func switchOn(consentedSourceID: String?) {
        isOn = true
        message = nil
        showsOpenSettings = false
        let sync = sync
        let workspace = workspaceID
        let previous = pendingTask
        generation += 1
        let action = generation
        switchOnsRunning += 1
        pendingTask = Task {
            defer { switchOnsRunning -= 1 }
            await previous?.value
            let result = await sync.enable(workspace: workspace, consentedSourceID: consentedSourceID)
            let destination = await sync.destination(workspace: workspace)
            // A later flip decides what the switch shows; this result is old news.
            guard action == generation else { return }
            self.destination = destination
            show(result)
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
        let action = generation
        pendingTask = Task {
            await previous?.value
            let removal = await sync.disable(workspace: workspace, removeCalendar: removeCalendar)
            guard action == generation else { return }
            destination = nil
            // The calendar also held the user's own events: it stayed, and the switch says why.
            if removal == .keptForUserEvents {
                message = WorkspaceStrings.calendarKeptForUserEvents
                showsOpenSettings = false
            }
        }
    }

    /// The app leaves the foreground: the "ook verwijderen?" question (with the workspace's name) must not stay
    /// above the lock screen. Not answering keeps the switch on.
    public func sceneLeftForeground() {
        isAskingToRemove = false
        // Not answering "mag dat?" is a no.
        if isAskingConsent { answerConsent(false) }
    }

    /// After the Workspaces list loaded, while the switch is on: says so when calendar access was taken away in
    /// Settings (and drops that line once it is back; the switch stays on either way), then syncs. A sync (this
    /// one or an earlier one elsewhere) that found the calendar's account gone turned the setting off: the switch
    /// follows and says so.
    public func refresh() {
        guard isOn else { return }
        let sync = sync
        let workspace = workspaceID
        let action = generation
        // A switch-on running now stores the setting at its end, or not at all (a question, no account, a
        // failure): an off setting then says nothing about the account.
        let startedDuringSwitchOn = switchOnsRunning > 0
        refreshTask = Task {
            let access = await sync.access()
            guard isOn, action == generation else { return }
            if access == .granted {
                if showsOpenSettings {
                    message = nil
                    showsOpenSettings = false
                }
            } else {
                message = WorkspaceStrings.calendarNoAccess
                showsOpenSettings = true
                return
            }
            let result = await sync.sync(workspace: workspace)
            let destination = await sync.destination(workspace: workspace)
            // A flip of the switch meanwhile decides what it shows.
            guard action == generation else { return }
            // Also when another sync (after a confirm or a ticked task) found the account gone and turned the
            // setting off: this sync then only answers `.off`.
            let turnedOffElsewhere = !startedDuringSwitchOn && switchOnsRunning == 0
                && !settings.isEnabled(for: workspace)
            if result == .sourceGone || turnedOffElsewhere {
                isOn = false
                message = WorkspaceStrings.calendarSourceGone
                showsOpenSettings = false
            }
            self.destination = destination
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
        case .needsConsent(let source):
            isOn = false
            consentSource = source
            isAskingConsent = true
        case .noCalendarAccount:
            isOn = false
            message = WorkspaceStrings.calendarNoCalendarAccount
            showsOpenSettings = false
        case .sourceGone:
            isOn = false
            message = WorkspaceStrings.calendarSourceGone
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
