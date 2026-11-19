@testable import BrievieCore
@testable import FeatureWorkspace
import Foundation
import Testing

/// "Herinneringen voor termijnen" in the settings: off until the user turns it on, the system's question at that
/// moment, "Open Instellingen" when refused, and the lead time and sender as simple settings.
@MainActor
@Suite struct ReminderSettingModelTests {
    private let center: InMemoryReminderCenter
    private let settings = InMemoryReminderSettings()
    private let workspace = UUID()
    private let openedSettings = OpenCount()
    private let reminders: DeadlineReminders

    init() {
        center = InMemoryReminderCenter(permission: .notDetermined, answer: true)
        reminders = Self.reminders(center: center, settings: settings, sender: "Gemeente")
    }

    private static func reminders(
        center: InMemoryReminderCenter, settings: InMemoryReminderSettings, sender: String
    ) -> DeadlineReminders {
        let task = WorkspaceTask(
            id: UUID(), type: "pay", description: "Betaal € 80", deadline: CalendarDate(year: 2026, month: 12, day: 20),
            isDone: false, documentID: nil, sender: sender
        )
        return DeadlineReminders(
            center: center, settings: settings, tasks: { _ in [task] },
            now: { Date(timeIntervalSince1970: 1_795_086_000) },
            timeZone: { TimeZone(identifier: "Europe/Amsterdam") ?? .gmt }
        )
    }

    /// The workspaces loaded once, so a refresh knows them.
    private func model() async -> ReminderSettingModel {
        await reminders.reschedule(workspaces: [workspace])
        return ReminderSettingModel(reminders: reminders) { [openedSettings] in openedSettings.count += 1 }
    }

    private var bodies: [String] {
        center.pending.values.sorted { $0.fireDate < $1.fireDate }.map(\.body)
    }

    @Test func offByDefaultWithThreeDaysAndNoSender() async {
        let model = await model()

        #expect(!model.isOn)
        #expect(model.leadDays == 3)
        #expect(!model.showsSender)
        #expect(center.pending.isEmpty)
        #expect(center.permissionRequests == 0)
    }

    @Test func turningOnAsksTheSystemThenSchedules() async {
        let model = await model()

        model.toggle(true)
        await model.pendingTask?.value

        #expect(center.permissionRequests == 1)
        #expect(model.isOn)
        #expect(settings.isEnabled())
        #expect(model.message == nil)
        #expect(bodies == ["Een termijn loopt over 3 dagen af.", "Een termijn loopt vandaag af."])
    }

    @Test func aRefusalTurnsItBackOffWithTheWayToSettings() async {
        let center = InMemoryReminderCenter(permission: .notDetermined, answer: false)
        let reminders = Self.reminders(center: center, settings: settings, sender: "Gemeente")
        let model = ReminderSettingModel(reminders: reminders) { [openedSettings] in openedSettings.count += 1 }

        model.toggle(true)
        await model.pendingTask?.value

        #expect(!model.isOn)
        #expect(!settings.isEnabled())
        #expect(model.message == WorkspaceStrings.remindersDenied)
        #expect(model.showsOpenSettings)
        model.openSettings()
        #expect(openedSettings.count == 1)
    }

    @Test func refusedEarlierItDoesNotAskAgain() async {
        center.setPermission(.denied)
        let model = await model()

        model.toggle(true)
        await model.pendingTask?.value

        #expect(center.permissionRequests == 0)
        #expect(!model.isOn)
        #expect(model.showsOpenSettings)
    }

    @Test func turningOffRemovesEveryReminder() async {
        let model = await model()
        model.toggle(true)
        await model.pendingTask?.value
        #expect(!center.pending.isEmpty)

        model.toggle(false)
        await model.pendingTask?.value

        #expect(!model.isOn)
        #expect(!settings.isEnabled())
        #expect(center.pending.isEmpty)
    }

    @Test func theLeadTimeIsASimpleSetting() async {
        let model = await model()
        model.toggle(true)
        await model.pendingTask?.value

        model.setLeadDays(7)
        await model.pendingTask?.value

        #expect(settings.leadDays() == 7)
        #expect(bodies == ["Een termijn loopt over 7 dagen af.", "Een termijn loopt vandaag af."])
        #expect(model.leadOptions.map(\.days) == [0, 1, 2, 3, 7])
        #expect(model.leadOptions.map(\.title) == [
            "Op de dag zelf", "1 dag ervoor", "2 dagen ervoor", "3 dagen ervoor", "1 week ervoor"
        ])
    }

    @Test func theSenderOnlyWhenTurnedOn() async {
        let model = await model()
        model.toggle(true)
        await model.pendingTask?.value

        model.setShowsSender(true)
        await model.pendingTask?.value

        #expect(settings.showsSender())
        #expect(bodies == [
            "Een termijn van Gemeente loopt over 3 dagen af.", "Een termijn van Gemeente loopt vandaag af."
        ])
    }

    @Test func theFooterSaysWhatIsShownAndWhatTheAppKnows() async {
        let model = await model()

        #expect(model.footer == """
            Je krijgt om 9:00 een melding, 3 dagen voordat een termijn afloopt en op de dag zelf. \
            In de melding staat alleen dat er een termijn afloopt, niets uit de brief. \
            Brievie herinnert je aan termijnen die de app kent. Open de app af en toe, dan blijft dat bij.
            """)

        model.toggle(true)
        await model.pendingTask?.value
        model.setLeadDays(0)
        model.setShowsSender(true)
        await model.pendingTask?.value
        #expect(model.footer.hasPrefix("Je krijgt om 9:00 een melding op de dag dat een termijn afloopt."))
        #expect(model.footer.contains("In de melding staat ook de afzender."))

        model.setLeadDays(1)
        await model.pendingTask?.value
        #expect(model.footer.hasPrefix("Je krijgt om 9:00 een melding, een dag voordat een termijn afloopt"))
    }

    @Test func withTheCalendarOnTooTheFooterSaysItRingsAsWell() async {
        let model = await model()
        model.calendarIsOn = { true }

        #expect(model.footer.hasSuffix(
            "Staat 'Zet termijnen in mijn agenda' ook aan? Dan meldt de agenda de termijnen ook."
        ))
    }

    @Test func permissionTakenAwayInSettingsIsShownAndClearedWhenBack() async {
        let model = await model()
        model.toggle(true)
        await model.pendingTask?.value

        center.setPermission(.denied)
        model.refresh()
        await model.refreshTask?.value
        #expect(model.isOn)
        #expect(model.message == WorkspaceStrings.remindersDenied)
        #expect(model.showsOpenSettings)

        center.setPermission(.allowed)
        model.refresh()
        await model.refreshTask?.value
        #expect(model.message == nil)
        #expect(!model.showsOpenSettings)
    }

    @Test func aRefreshWhileTheQuestionIsOpenKeepsTheSwitchOn() async {
        let model = await model()

        model.toggle(true)
        // The workspaces load meanwhile (the setting is stored only after the answer).
        model.refresh()
        #expect(model.isOn)
        await model.pendingTask?.value

        #expect(model.isOn)
        #expect(settings.isEnabled())
    }

    @Test func aSwitchTurnedOffElsewhereFollows() async {
        // Forgetting the pairing turns the setting off; a model made before shows it after a refresh.
        let model = await model()
        model.toggle(true)
        await model.pendingTask?.value

        settings.removeAll()
        model.refresh()
        await model.refreshTask?.value

        #expect(!model.isOn)
        #expect(model.leadDays == 3)
    }
}

/// How often "Open Instellingen" opened the Settings app.
@MainActor
private final class OpenCount {
    var count = 0
}
