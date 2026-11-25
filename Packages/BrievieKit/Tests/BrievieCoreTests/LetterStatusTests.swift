@testable import BrievieCore
import Foundation
import Testing

/// Letter status (host PR #50): the status reads with a default from an older server, the new refusals have
/// their own verdicts, and the reminders follow waiting and snoozed tasks.
@Suite struct LetterStatusTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")
    private static let amsterdam = TimeZone(identifier: "Europe/Amsterdam") ?? .gmt

    @Test(arguments: [
        (nil, LetterStatus.none), ("", .none), ("new", .new), ("open", .open), ("waiting", .waiting),
        ("handled", .handled), ("later_value", .unknown)
    ] as [(String?, LetterStatus)])
    func anOlderServerHasNoStatus(api: String?, expected: LetterStatus) {
        #expect(LetterStatus(api: api) == expected)
    }

    @Test(arguments: ["tasks_changed", "payment_not_confirmed", "document_not_reviewed", "task_done"])
    func the409sPassThrough(code: String) {
        #expect(ServerError(status: 409, code: code) == .other(code))
    }

    @Test func handlingWithChangedTasksIsItsOwnVerdict() async throws {
        let store = ConnectionStore(secrets: InMemorySecretStore())
        let connection = ServerConnection(urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Lid")
        try store.save(connection, token: "tok")
        let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
        server.onHandleDocument { _, _, _, _ in throw ServerError.other("tasks_changed") }
        let documents = WorkspaceDocuments(workspaceID: UUID(), connection: connection, store: store, server: server)
        let id = UUID()
        let task = UUID()

        await #expect(throws: DocumentsError.tasksChanged) {
            try await documents.handleDocument(id, taskIDs: [task], paymentsConfirmed: true)
        }
        #expect(server.calls.contains(.handleDocument(Self.url, id, [task], paymentsConfirmed: true)))
    }

    // MARK: - Reminders

    private func task(group: TaskGroup, waitingUntil: CalendarDate? = nil) -> ReminderTask {
        ReminderTask(workspaceID: UUID(), task: WorkspaceTask(
            id: UUID(), type: "respond", description: "Reageer", deadline: CalendarDate(year: 2026, month: 12, day: 10),
            isDone: false, documentID: UUID(), sender: "Gemeente", group: group, waitingUntil: waitingUntil
        ))
    }

    private var now: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.amsterdam
        return calendar.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 12)) ?? .distantPast
    }

    @Test func aWaitingTaskGetsOnlyAWaitOverReminderAtNine() throws {
        let until = CalendarDate(year: 2026, month: 12, day: 20)

        let plan = ReminderPlanner.plan(
            [task(group: .waiting, waitingUntil: until)], now: now, timeZone: Self.amsterdam, leadDays: 3,
            showsSender: false
        )

        let reminder = try #require(plan.first)
        #expect(plan.count == 1)
        #expect(reminder.kind == .waitOver)
        #expect(reminder.day == until)
        #expect(reminder.hour == 9)
        #expect(reminder.body == AppStrings.reminderWaitOver)
        #expect(ReminderPlanner.parse(reminder.identifier) != nil)
    }

    @Test func theSenderOnlyWhenChosen() throws {
        let plan = ReminderPlanner.plan(
            [task(group: .waiting, waitingUntil: CalendarDate(year: 2026, month: 12, day: 20))], now: now,
            timeZone: Self.amsterdam, leadDays: 3, showsSender: true
        )

        #expect(try #require(plan.first).body.contains("Gemeente"))
    }

    @Test func aSnoozedTaskGetsNoReminder() {
        let plan = ReminderPlanner.plan(
            [task(group: .snoozed)], now: now, timeZone: Self.amsterdam, leadDays: 3, showsSender: false
        )

        #expect(plan.isEmpty)
    }

    @Test func anOrdinaryTaskKeepsItsDeadlineReminders() {
        let plan = ReminderPlanner.plan(
            [task(group: .later)], now: now, timeZone: Self.amsterdam, leadDays: 3, showsSender: false
        )

        #expect(plan.map(\.kind) == [.ahead, .onTheDay])
    }
}
