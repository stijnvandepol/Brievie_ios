import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// Letter status in the app (host PR #50): the badge, "Brief afhandelen", and waiting and snoozing in Mijn taken.
@MainActor
@Suite struct LetterStatusModelTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")
    private static let dutch = Locale(identifier: "nl_NL")

    nonisolated private static func summary(_ status: LetterStatus, overdue: Bool = false, until: CalendarDate? = nil)
        -> DocumentSummary {
        DocumentSummary(
            id: UUID(), clientID: UUID(), status: .done, pageCount: 1, createdAt: Date(timeIntervalSince1970: 0),
            sender: "Gemeente", documentType: "letter", letterDate: nil, letterStatus: status, isOverdue: overdue,
            waitingUntil: until
        )
    }

    // MARK: - Badge

    @Test func noBadgeFromAnOlderServer() {
        #expect(LetterStatusWords.badge(for: Self.summary(.none)) == nil)
        #expect(LetterStatusWords.badge(for: Self.summary(.unknown)) == nil)
    }

    @Test func waitingNamesTheDayAndOverdueIsSaidInWords() throws {
        let badge = try #require(LetterStatusWords.badge(
            for: Self.summary(.waiting, until: CalendarDate(year: 2026, month: 12, day: 3)), locale: Self.dutch
        ))
        #expect(badge.text.hasPrefix("Wacht op reactie tot 3"))

        let late = try #require(LetterStatusWords.badge(for: Self.summary(.open, overdue: true)))
        #expect(late.text == DocumentStrings.letterStatusOpen)
        #expect(late.accessibilityText.contains(DocumentStrings.letterStatusOverdue))
    }

    // MARK: - Brief afhandelen

    private func letterModel(server: FakeDocumentServer, tasks: [ConfirmedTask]) throws -> ConfirmedDocumentModel {
        let store = ConnectionStore(secrets: InMemorySecretStore())
        let connection = ServerConnection(urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Lid")
        try store.save(connection, token: "tok")
        let detail = DocumentDetail(
            summary: Self.summary(.open), failureCode: "", summaryText: "", summaryByAI: false, pageTexts: [],
            proposals: [], tasks: tasks
        )
        return ConfirmedDocumentModel(
            detail: detail, persons: [], labels: [],
            documents: WorkspaceDocuments(workspaceID: UUID(), connection: connection, store: store, server: server),
            canEdit: true, onRevoked: {}, onMissingPairing: {}
        )
    }

    private static func task(_ type: String, _ description: String, done: Bool = false) -> ConfirmedTask {
        ConfirmedTask(
            id: UUID(), type: type, description: description, deadline: nil, deadlineSource: "manual",
            deadlineQuote: "", isDone: done
        )
    }

    @Test func theSheetNamesTheOpenTasksAndAsksForThePayment() throws {
        let pay = Self.task("pay", "Betaal de aanslag")
        let done = Self.task("respond", "Al gedaan", done: true)
        let model = try letterModel(server: FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }, tasks: [
            pay, done
        ])

        #expect(model.canHandle)
        model.startHandling()

        let sheet = try #require(model.handleSheet)
        #expect(sheet.taskIDs == [pay.id])
        #expect(sheet.taskTitles == ["Betaal de aanslag"])
        #expect(sheet.needsPayment)
    }

    @Test func changedTasksReloadTheSheetWithTheReason() async throws {
        let first = Self.task("respond", "Reageer")
        let added = Self.task("respond", "Stuur het formulier")
        let server = FakeDocumentServer { _, _ in
            DocumentDetail(
                summary: Self.summary(.open), failureCode: "", summaryText: "", summaryByAI: false, pageTexts: [],
                proposals: [], tasks: [first, added]
            )
        }
        server.onHandleDocument { _, _, _, _ in throw ServerError.other("tasks_changed") }
        let model = try letterModel(server: server, tasks: [first])
        model.startHandling()

        await model.handle(paymentsConfirmed: false)

        #expect(model.handleSheet?.taskIDs == [first.id, added.id])
        #expect(model.handleError == DocumentStrings.errorTasksChanged)
    }

    @Test func handlingClosesTheSheetAndShowsTheAnswer() async throws {
        let open = Self.task("respond", "Reageer")
        let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
        let model = try letterModel(server: server, tasks: [open])
        let handled = DocumentDetail(
            summary: Self.summary(.handled), failureCode: "", summaryText: "", summaryByAI: false, pageTexts: [],
            proposals: [], tasks: []
        )
        server.onHandleDocument { _, _, _, _ in handled }
        model.startHandling()

        await model.handle(paymentsConfirmed: false)

        #expect(model.handleSheet == nil)
        #expect(model.letterBadge?.status == .handled)
        #expect(!model.canHandle)
    }

    // MARK: - Mijn taken

    @Test func waitingAndSnoozedTasksGetTheirOwnGroups() async throws {
        let harness = try MyTasksHarness()
        let waiting = WorkspaceTask(
            id: UUID(), type: "respond", description: "Reageer", deadline: nil, isDone: false, documentID: UUID(),
            sender: "Gemeente", group: .waiting, waitingUntil: CalendarDate(year: 2026, month: 12, day: 3)
        )
        let snoozed = WorkspaceTask(
            id: UUID(), type: "pay", description: "Betaal", deadline: nil, isDone: false, documentID: UUID(),
            sender: "Gemeente", group: .snoozed, snoozedUntil: CalendarDate(year: 2026, month: 12, day: 1)
        )
        harness.serve([MyTasksHarness.task(), waiting, snoozed])

        await harness.model.load()

        #expect(harness.model.sections.map(\.group) == [.later])
        #expect(harness.model.parkedSections.map(\.group) == [.waiting, .snoozed])
        let row = try #require(harness.model.parkedSections.first?.rows.first)
        #expect(row.parkedLine?.hasPrefix("Wacht op reactie tot 3") == true)
        #expect(row.isWaiting)
    }

    @Test func snoozingStopsAtTheTasksDate() async throws {
        let harness = try MyTasksHarness()
        let deadline = MyTasksHarness.today.adding(days: 5)
        let task = MyTasksHarness.task(deadline: deadline)
        harness.serve([task])
        await harness.model.load()

        harness.model.startSnoozing(task.id)

        guard case let .snooze(_, _, _, range)? = harness.model.sheet else {
            Issue.record("No snooze sheet")
            return
        }
        #expect(range == MyTasksHarness.today.adding(days: 1)...deadline)
    }

    @Test func aTaskDueTodayCannotBeSnoozed() async throws {
        let harness = try MyTasksHarness()
        let task = MyTasksHarness.task(deadline: MyTasksHarness.today)
        harness.serve([task])
        await harness.model.load()

        let row = try #require(harness.model.sections.first?.rows.first)
        #expect(!row.canSnooze)
    }

    @Test func waitingIsSentAndTheListLoadsAgain() async throws {
        let harness = try MyTasksHarness()
        let task = MyTasksHarness.task()
        harness.serve([task])
        await harness.model.load()
        let until = MyTasksHarness.today.adding(days: 14)
        harness.model.startWaiting(task.id)

        await harness.model.setWaiting(until, for: task.id)

        #expect(harness.server.calls.contains(.setTaskWaiting(MyTasksHarness.url, task.id, until)))
        #expect(harness.model.sheet == nil)
        #expect(harness.myTasksCalls.count == 2)
    }
}
