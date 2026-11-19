@testable import BrievieCore
import Foundation
import Testing

/// Which reminders exist for a task list: a few days before and on the day, at 09:00 in the phone's time zone,
/// never for what is done or past, the nearest first up to the system's 64, and nothing from the letter by default.
@Suite struct ReminderPlannerTests {
    private static let amsterdam = TimeZone(identifier: "Europe/Amsterdam") ?? .gmt
    private static let losAngeles = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
    private let home = UUID()

    private static func task(
        _ deadline: CalendarDate?, isDone: Bool = false, id: UUID = UUID(), document: UUID? = UUID(),
        description: String = "Betaal € 123,45 voor de eigen bijdrage", sender: String = "CAK"
    ) -> WorkspaceTask {
        WorkspaceTask(
            id: id, type: "pay", description: description, deadline: deadline, isDone: isDone, documentID: document,
            sender: sender
        )
    }

    /// `hour:minute` on a day in a time zone.
    private static func time(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, in zone: TimeZone = amsterdam
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
            ?? .distantPast
    }

    private func plan(
        _ tasks: [WorkspaceTask], now: Date, zone: TimeZone = amsterdam, leadDays: Int = 3, showsSender: Bool = false,
        limit: Int = ReminderPlanner.maxPending
    ) -> [DeadlineReminder] {
        ReminderPlanner.plan(
            tasks.map { ReminderTask(workspaceID: home, task: $0) }, now: now, timeZone: zone, leadDays: leadDays,
            showsSender: showsSender, limit: limit
        )
    }

    // MARK: Which reminders

    @Test func aDeadlineGetsOneAheadAndOneOnTheDayAtNine() {
        let task = Self.task(CalendarDate(year: 2026, month: 12, day: 10))

        let reminders = plan([task], now: Self.time(2026, 11, 19, 12))

        #expect(reminders.map(\.kind) == [.ahead, .onTheDay])
        #expect(reminders.map(\.day) == [
            CalendarDate(year: 2026, month: 12, day: 7), CalendarDate(year: 2026, month: 12, day: 10)
        ])
        #expect(reminders.map(\.fireDate) == [Self.time(2026, 12, 7, 9), Self.time(2026, 12, 10, 9)])
        #expect(reminders.allSatisfy { $0.taskID == task.id && $0.workspaceID == home })
        #expect(reminders.allSatisfy { $0.documentID == task.documentID })
    }

    @Test func noRemindersForADoneTaskATaskWithoutDeadlineOrAPastDeadline() {
        let now = Self.time(2026, 11, 19, 8)
        let tasks = [
            Self.task(CalendarDate(year: 2026, month: 12, day: 10), isDone: true),
            Self.task(nil),
            Self.task(CalendarDate(year: 2026, month: 11, day: 18))
        ]

        #expect(plan(tasks, now: now).isEmpty)
    }

    @Test func aReminderWhoseMomentHasPassedIsLeftOut() {
        let deadline = CalendarDate(year: 2026, month: 11, day: 20)
        // On the day before nine: still that one; after nine: nothing.
        #expect(plan([Self.task(deadline)], now: Self.time(2026, 11, 20, 8, 59)).map(\.kind) == [.onTheDay])
        #expect(plan([Self.task(deadline)], now: Self.time(2026, 11, 20, 9)).isEmpty)
    }

    @Test(arguments: [0, 1, 2, 3, 7])
    func theLeadTimeIsASetting(leadDays: Int) {
        let deadline = CalendarDate(year: 2026, month: 12, day: 10)

        let reminders = plan([Self.task(deadline)], now: Self.time(2026, 11, 19, 12), leadDays: leadDays)

        let expected = leadDays == 0 ? [deadline] : [deadline.adding(days: -leadDays), deadline]
        #expect(reminders.map(\.day) == expected)
    }

    // MARK: Time zones, midnight and summer time

    @Test func justBeforeMidnightTheNextDaysDeadlineStillGetsItsReminder() {
        let deadline = CalendarDate(year: 2026, month: 11, day: 20)

        let reminders = plan([Self.task(deadline)], now: Self.time(2026, 11, 19, 23, 59))

        #expect(reminders.map(\.fireDate) == [Self.time(2026, 11, 20, 9)])
    }

    @Test func justAfterMidnightYesterdaysDeadlineIsPast() {
        let deadline = CalendarDate(year: 2026, month: 11, day: 19)

        #expect(plan([Self.task(deadline)], now: Self.time(2026, 11, 20, 0, 1)).isEmpty)
    }

    @Test func theDayIsTheDayOfThePhonesTimeZone() {
        // 07:00 UTC on November 20 is 08:00 in Amsterdam but still November 19, 23:00 in Los Angeles.
        let now = Date(timeIntervalSince1970: 1_795_158_000)
        let deadline = CalendarDate(year: 2026, month: 11, day: 20)
        let lead = CalendarDate(year: 2026, month: 11, day: 19)

        let inAmsterdam = plan([Self.task(deadline)], now: now, leadDays: 1)
        let inLosAngeles = plan([Self.task(deadline)], now: now, zone: Self.losAngeles, leadDays: 1)

        #expect(inAmsterdam.map(\.day) == [deadline])
        #expect(inAmsterdam.map(\.fireDate) == [Self.time(2026, 11, 20, 9)])
        // In Los Angeles the lead day is today and its nine o'clock has passed; the day itself is still ahead.
        #expect(inLosAngeles.map(\.day) == [deadline])
        #expect(inLosAngeles.map(\.fireDate) == [Self.time(2026, 11, 20, 9, in: Self.losAngeles)])
        #expect(!inLosAngeles.map(\.day).contains(lead))
    }

    @Test func nineOClockStaysNineAcrossTheChangeToSummerTime() {
        // Summer time starts on 2027-03-28 in Amsterdam: 09:00 is 08:00 UTC before and 07:00 UTC after.
        let deadline = CalendarDate(year: 2027, month: 3, day: 29)

        let reminders = plan([Self.task(deadline)], now: Self.time(2027, 3, 1, 12))

        #expect(reminders.map(\.fireDate) == [Self.time(2027, 3, 26, 9), Self.time(2027, 3, 29, 9)])
        #expect(reminders.map { $0.fireDate.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400) }
            == [8 * 3_600, 7 * 3_600])
        #expect(reminders.allSatisfy { $0.hour == 9 && $0.minute == 0 })
    }

    @Test func nineOClockStaysNineAcrossTheChangeToWinterTime() {
        // Winter time starts on 2026-10-25 in Amsterdam.
        let deadline = CalendarDate(year: 2026, month: 10, day: 26)

        let reminders = plan([Self.task(deadline)], now: Self.time(2026, 10, 1, 12))

        #expect(reminders.map(\.fireDate) == [Self.time(2026, 10, 23, 9), Self.time(2026, 10, 26, 9)])
        #expect(reminders[1].fireDate.timeIntervalSince(reminders[0].fireDate) == 3 * 86_400 + 3_600)
    }

    // MARK: The system's limit

    @Test func atMost64AndTheNearestFirst() {
        let start = CalendarDate(year: 2026, month: 12, day: 1)
        let tasks = (0..<50).map { Self.task(start.adding(days: $0)) }

        let reminders = plan(tasks.shuffled(), now: Self.time(2026, 11, 19, 12))

        #expect(reminders.count == 64)
        #expect(reminders.map(\.fireDate) == reminders.map(\.fireDate).sorted())
        // 100 candidates: the 64 kept all come before the 36 left out.
        let all = plan(tasks, now: Self.time(2026, 11, 19, 12), limit: 1_000)
        #expect(all.count == 100)
        let lastKept = reminders.map(\.fireDate).max() ?? .distantPast
        #expect(all.dropFirst(64).allSatisfy { $0.fireDate >= lastKept })
    }

    @Test func aSmallerRoomIsRespected() {
        let tasks = (0..<5).map { Self.task(CalendarDate(year: 2026, month: 12, day: 1).adding(days: $0)) }

        #expect(plan(tasks, now: Self.time(2026, 11, 19, 12), limit: 3).count == 3)
        #expect(plan(tasks, now: Self.time(2026, 11, 19, 12), limit: 0).isEmpty)
    }

    // MARK: What the lock screen shows

    @Test func byDefaultTheTextCarriesNothingFromTheLetter() {
        let task = Self.task(
            CalendarDate(year: 2026, month: 12, day: 10), description: "Betaal € 123,45 aan het CAK", sender: "CAK"
        )

        let reminders = plan([task], now: Self.time(2026, 11, 19, 12))

        #expect(reminders.map(\.body) == [
            "Een termijn loopt over 3 dagen af.", "Een termijn loopt vandaag af."
        ])
        for reminder in reminders {
            #expect(!reminder.body.contains("CAK"))
            #expect(!reminder.body.contains("123"))
            #expect(!reminder.body.contains("Betaal"))
        }
    }

    @Test func tomorrowSaysTomorrow() {
        let reminders = plan(
            [Self.task(CalendarDate(year: 2026, month: 12, day: 10))], now: Self.time(2026, 11, 19, 12), leadDays: 1
        )

        #expect(reminders.first?.body == "Een termijn loopt morgen af.")
    }

    @Test func theSenderOnlyWhenAskedAndNeverTheAmountOrDescription() {
        let task = Self.task(
            CalendarDate(year: 2026, month: 12, day: 10), description: "Betaal € 123,45", sender: "  Belastingdienst \n"
        )

        let reminders = plan([task], now: Self.time(2026, 11, 19, 12), showsSender: true)

        #expect(reminders.map(\.body) == [
            "Een termijn van Belastingdienst loopt over 3 dagen af.",
            "Een termijn van Belastingdienst loopt vandaag af."
        ])
        #expect(reminders.allSatisfy { !$0.body.contains("123") && !$0.body.contains("Betaal") })
    }

    @Test func aTaskWithoutSenderUsesThePlainTextEvenWhenAsked() {
        let task = Self.task(CalendarDate(year: 2026, month: 12, day: 10), sender: " ")

        let reminders = plan([task], now: Self.time(2026, 11, 19, 12), showsSender: true)

        #expect(reminders.last?.body == "Een termijn loopt vandaag af.")
    }

    @Test func aVeryLongSenderIsCut() {
        let sender = String(repeating: "Gemeente ", count: 20)
        let task = Self.task(CalendarDate(year: 2026, month: 12, day: 10), sender: sender)

        let body = plan([task], now: Self.time(2026, 11, 19, 12), showsSender: true).last?.body ?? ""

        #expect(body.count < 100)
        #expect(body.contains("…"))
    }

    // MARK: Identity

    @Test func theIdentifierNamesWorkspaceTaskAndKindAndReadsBack() {
        let task = Self.task(CalendarDate(year: 2026, month: 12, day: 10))

        let reminders = plan([task], now: Self.time(2026, 11, 19, 12))

        #expect(Set(reminders.map(\.identifier)).count == 2)
        for reminder in reminders {
            let parsed = ReminderPlanner.parse(reminder.identifier)
            #expect(parsed == ReminderIdentity(workspaceID: home, taskID: task.id))
        }
        #expect(ReminderPlanner.parse("something.else") == nil)
        #expect(ReminderPlanner.parse("deadline.not-a-uuid.\(task.id.uuidString).day") == nil)
    }

    // MARK: Catching up a first notice that came too late

    @Test func confirmedTheEveningBeforeOnlyTheDayItself() {
        let deadline = CalendarDate(year: 2026, month: 11, day: 20)

        let reminders = plan([Self.task(deadline)], now: Self.time(2026, 11, 19, 20))

        // The next nine o'clock is the deadline's own: never two notices on one day.
        #expect(reminders.map(\.kind) == [.onTheDay])
        #expect(reminders.map(\.fireDate) == [Self.time(2026, 11, 20, 9)])
    }

    @Test func confirmedOnTheDayAfterNineNothing() {
        let deadline = CalendarDate(year: 2026, month: 11, day: 20)

        #expect(plan([Self.task(deadline)], now: Self.time(2026, 11, 20, 9, 30)).isEmpty)
    }

    @Test func confirmedOnTheDayBeforeNineOnlyTheDayItself() {
        let deadline = CalendarDate(year: 2026, month: 11, day: 20)

        #expect(plan([Self.task(deadline)], now: Self.time(2026, 11, 20, 7)).map(\.kind) == [.onTheDay])
    }

    @Test func aLateFirstNoticeComesTomorrowAtNine() {
        // Three days ahead was November 17; on the evening of the 18th it comes on the 19th, "morgen".
        let deadline = CalendarDate(year: 2026, month: 11, day: 20)

        let reminders = plan([Self.task(deadline)], now: Self.time(2026, 11, 18, 20))

        #expect(reminders.map(\.fireDate) == [Self.time(2026, 11, 19, 9), Self.time(2026, 11, 20, 9)])
        #expect(reminders.map(\.body) == ["Een termijn loopt morgen af.", "Een termijn loopt vandaag af."])
    }

    @Test func aLateFirstNoticeComesTodayWhenItIsBeforeNine() {
        let deadline = CalendarDate(year: 2026, month: 11, day: 20)

        let reminders = plan([Self.task(deadline)], now: Self.time(2026, 11, 15, 8), leadDays: 7)

        #expect(reminders.map(\.fireDate) == [Self.time(2026, 11, 15, 9), Self.time(2026, 11, 20, 9)])
        #expect(reminders.first?.body == "Een termijn loopt over 5 dagen af.")
    }

    @Test func aCatchUpIsMadeOnce() {
        let task = Self.task(CalendarDate(year: 2026, month: 11, day: 20))
        let first = ReminderPlanner.schedule(
            [ReminderTask(workspaceID: home, task: task)], now: Self.time(2026, 11, 13, 20),
            timeZone: Self.amsterdam, leadDays: 7, showsSender: false
        )
        #expect(first.reminders.map(\.day.day) == [14, 20])
        #expect(first.catchUps.values.map(\.day.day) == [14])

        // Refreshed before it went off: the same day. After it went off: no second one on the 15th.
        let before = ReminderPlanner.schedule(
            [ReminderTask(workspaceID: home, task: task)], now: Self.time(2026, 11, 13, 23),
            timeZone: Self.amsterdam, leadDays: 7, showsSender: false, catchUps: first.catchUps
        )
        #expect(before.reminders.map(\.day.day) == [14, 20])
        let after = ReminderPlanner.schedule(
            [ReminderTask(workspaceID: home, task: task)], now: Self.time(2026, 11, 14, 12),
            timeZone: Self.amsterdam, leadDays: 7, showsSender: false, catchUps: before.catchUps
        )
        #expect(after.reminders.map(\.kind) == [.onTheDay])
        #expect(after.catchUps == first.catchUps)
    }

    @Test func aMovedDeadlineStartsAfresh() {
        let id = UUID()
        let old = Self.task(CalendarDate(year: 2026, month: 11, day: 20), id: id)
        let first = ReminderPlanner.schedule(
            [ReminderTask(workspaceID: home, task: old)], now: Self.time(2026, 11, 13, 20),
            timeZone: Self.amsterdam, leadDays: 7, showsSender: false
        )
        let moved = Self.task(CalendarDate(year: 2026, month: 11, day: 25), id: id)

        let again = ReminderPlanner.schedule(
            [ReminderTask(workspaceID: home, task: moved)], now: Self.time(2026, 11, 14, 12),
            timeZone: Self.amsterdam, leadDays: 7, showsSender: false, catchUps: first.catchUps
        )

        // Seven days before the 25th is the 18th, still ahead: the planned notice, no catch-up remembered.
        #expect(again.reminders.map(\.day.day) == [18, 25])
        #expect(again.catchUps.isEmpty)
    }

    @Test func aCatchUpLeftOutByTheLimitIsNotRemembered() {
        let task = Self.task(CalendarDate(year: 2026, month: 11, day: 20))

        let plan = ReminderPlanner.schedule(
            [ReminderTask(workspaceID: home, task: task)], now: Self.time(2026, 11, 13, 20),
            timeZone: Self.amsterdam, leadDays: 7, showsSender: false, limit: 0
        )

        #expect(plan.catchUps.isEmpty)
    }
}
