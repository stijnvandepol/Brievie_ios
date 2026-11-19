import BrievieCore
import Foundation
import Observation

/// What the settings need for the deadline reminders. The app supplies it; without it there is no switch.
public struct WorkspaceReminders {
    let reminders: DeadlineReminders
    let openSettings: @MainActor () -> Void

    public init(reminders: DeadlineReminders, openSettings: @escaping @MainActor () -> Void) {
        self.reminders = reminders
        self.openSettings = openSettings
    }
}

/// "Herinneringen voor termijnen": one switch for this phone, with the lead time and "Toon de afzender in
/// herinneringen" under it while it is on.
@MainActor
@Observable
public final class ReminderSettingModel {
    public private(set) var isOn: Bool
    public private(set) var leadDays: Int
    public private(set) var showsSender: Bool
    /// Why the switch went back off, or that notifications were switched off in Settings; `nil` for nothing.
    public private(set) var message: String?
    /// The message is about refused notifications: offer "Open Instellingen".
    public private(set) var showsOpenSettings = false

    private let reminders: DeadlineReminders
    private let openSystemSettings: @MainActor () -> Void
    /// The work of the switch and its settings, in the order of the taps. Tests await it.
    @ObservationIgnored private(set) var pendingTask: Task<Void, Never>?
    /// The permission check after the workspaces loaded. Tests await it.
    @ObservationIgnored private(set) var refreshTask: Task<Void, Never>?
    /// Taps whose work has not ended: until then the switch shows the tap, not the stored setting.
    @ObservationIgnored private var tapsRunning = 0

    public init(reminders: DeadlineReminders, openSettings: @escaping @MainActor () -> Void) {
        self.reminders = reminders
        openSystemSettings = openSettings
        isOn = reminders.settings.isEnabled()
        leadDays = reminders.settings.leadDays()
        showsSender = reminders.settings.showsSender()
    }

    /// The lead times to choose from, with their names ("3 dagen ervoor").
    public var leadOptions: [(days: Int, title: String)] {
        ReminderPlanner.leadOptions.map { ($0, WorkspaceStrings.reminderLeadOption($0)) }
    }

    /// Under the switch: when a reminder comes, what it shows, and that it only knows what the app last read.
    public var footer: String {
        let when = switch leadDays {
        case 0: WorkspaceStrings.remindersWhenOnTheDay
        case 1: WorkspaceStrings.remindersWhenDayBefore
        default: String(format: WorkspaceStrings.remindersWhenDaysBeforeFormat, leadDays)
        }
        let shown = showsSender ? WorkspaceStrings.remindersShowSender : WorkspaceStrings.remindersShowNothing
        return "\(when) \(shown) \(WorkspaceStrings.remindersKnownOnly)"
    }

    /// The switch was flipped. On: asks the system at this moment (only when it never asked), then schedules; a
    /// refusal turns it back off with "Open Instellingen". Off: every reminder goes.
    public func toggle(_ wantsOn: Bool) {
        guard wantsOn != isOn else { return }
        isOn = wantsOn
        message = nil
        showsOpenSettings = false
        let reminders = reminders
        guard wantsOn else {
            reminders.settings.setEnabled(false)
            queue { await reminders.removeAll() }
            return
        }
        queue { [weak self] in
            guard await reminders.requestPermission() else {
                self?.refused()
                return
            }
            // Turned off again while the question was open: that tap wins.
            guard self?.isOn == true else { return }
            reminders.settings.setEnabled(true)
            await reminders.reschedule()
        }
    }

    public func setLeadDays(_ days: Int) {
        guard days != leadDays, ReminderPlanner.leadOptions.contains(days) else { return }
        leadDays = days
        reminders.settings.setLeadDays(days)
        rescheduleIfOn()
    }

    /// "Toon de afzender in herinneringen".
    public func setShowsSender(_ shows: Bool) {
        guard shows != showsSender else { return }
        showsSender = shows
        reminders.settings.setShowsSender(shows)
        rescheduleIfOn()
    }

    /// After the workspaces loaded: follows a setting changed elsewhere (forgotten with the pairing), and says so
    /// when notifications were switched off in Settings while reminders are on (the switch stays on; reminders
    /// come again once they are allowed).
    public func refresh() {
        // A switch-on waiting for the system's question stores the setting at its end.
        guard tapsRunning == 0 else { return }
        let settings = reminders.settings
        isOn = settings.isEnabled()
        leadDays = settings.leadDays()
        showsSender = settings.showsSender()
        guard isOn else {
            if showsOpenSettings { clearMessage() }
            return
        }
        let reminders = reminders
        refreshTask = Task {
            let permission = await reminders.permission()
            guard isOn else { return }
            if permission == .allowed {
                if showsOpenSettings { clearMessage() }
            } else {
                message = WorkspaceStrings.remindersDenied
                showsOpenSettings = true
            }
        }
    }

    /// "Open Instellingen", after notifications were refused.
    public func openSettings() {
        openSystemSettings()
    }

    private func rescheduleIfOn() {
        guard isOn else { return }
        let reminders = reminders
        queue { await reminders.reschedule() }
    }

    private func refused() {
        isOn = false
        reminders.settings.setEnabled(false)
        message = WorkspaceStrings.remindersDenied
        showsOpenSettings = true
    }

    private func clearMessage() {
        message = nil
        showsOpenSettings = false
    }

    private func queue(_ work: @escaping @MainActor () async -> Void) {
        let previous = pendingTask
        tapsRunning += 1
        pendingTask = Task {
            defer { tapsRunning -= 1 }
            await previous?.value
            await work()
        }
    }
}
