@testable import BrievieCore
import Foundation
import Testing
import UserNotifications

/// What the system gets for a reminder, and what a tap on it leads to.
@Suite struct ReminderRequestTests {
    private let workspace = UUID()
    private let document = UUID()

    private func reminder(document: UUID?) -> DeadlineReminder {
        let task = WorkspaceTask(
            id: UUID(), type: "pay", description: "Betaal € 80 aan CAK",
            deadline: CalendarDate(year: 2026, month: 12, day: 10), isDone: false, documentID: document, sender: "CAK"
        )
        let reminders = ReminderPlanner.plan(
            [ReminderTask(workspaceID: workspace, task: task)], now: Date(timeIntervalSince1970: 1_795_086_000),
            timeZone: TimeZone(identifier: "Europe/Amsterdam") ?? .gmt, leadDays: 0, showsSender: false
        )
        return reminders[0]
    }

    @Test func theRequestRingsAtNineInWhateverZoneThePhoneIsIn() throws {
        let request = UserNotificationsReminderCenter.request(for: reminder(document: document))

        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(!trigger.repeats)
        #expect(trigger.dateComponents.timeZone == nil)
        #expect(trigger.dateComponents.year == 2026)
        #expect(trigger.dateComponents.month == 12)
        #expect(trigger.dateComponents.day == 10)
        #expect(trigger.dateComponents.hour == 9)
        #expect(trigger.dateComponents.minute == 0)
    }

    @Test func theRequestShowsOnlyTheNeutralSentenceAndCarriesIdsOnly() {
        let request = UserNotificationsReminderCenter.request(for: reminder(document: document))

        #expect(request.content.title.isEmpty)
        #expect(request.content.subtitle.isEmpty)
        #expect(request.content.body == "Een termijn loopt vandaag af.")
        let values = request.content.userInfo.values.compactMap { $0 as? String }
        #expect(Set(values) == [workspace.uuidString, document.uuidString])
    }

    @Test func aTapLeadsToTheWorkspaceAndTheLetter() {
        let request = UserNotificationsReminderCenter.request(for: reminder(document: document))

        #expect(ReminderTarget(userInfo: request.content.userInfo)
            == ReminderTarget(workspaceID: workspace, documentID: document))
    }

    @Test func aTaskWithoutLetterLeadsToItsWorkspace() {
        let request = UserNotificationsReminderCenter.request(for: reminder(document: nil))

        #expect(ReminderTarget(userInfo: request.content.userInfo)
            == ReminderTarget(workspaceID: workspace, documentID: nil))
    }

    @Test func anythingElseLeadsNowhere() {
        #expect(ReminderTarget(userInfo: [:]) == nil)
        #expect(ReminderTarget(userInfo: ["workspace": "not-a-uuid"]) == nil)
    }

    @Test @MainActor func theRouterHoldsATargetUntilItIsShown() {
        let router = ReminderRouter()
        let target = ReminderTarget(workspaceID: workspace, documentID: document)

        router.open(target)
        #expect(router.target == target)

        router.finish()
        #expect(router.target == nil)
    }
}
