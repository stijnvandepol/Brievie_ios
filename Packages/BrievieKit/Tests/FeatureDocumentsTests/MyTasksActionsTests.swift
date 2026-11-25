import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// "Ik doe dit", "Niet meer aan mij", "Geef aan…" and "Datum invullen" in Mijn taken.
@MainActor
@Suite struct MyTasksActionsTests {
    private typealias Harness = MyTasksHarness
    private static let anne = UUID()

    private func loaded(_ tasks: [WorkspaceTask], canEdit: Bool = true) async throws -> Harness {
        let harness = try Harness(canEdit: canEdit)
        harness.serve(tasks)
        await harness.model.load()
        return harness
    }

    private func row(_ harness: Harness, _ id: UUID) -> MyTasksModel.Row? {
        harness.model.sections.flatMap(\.rows).first { $0.id == id }
    }

    @Test func takeOnAssignsToMeAndReloads() async throws {
        let first = Harness.task(reason: .unassigned)
        let second = Harness.task(reason: .department)
        let harness = try await loaded([first, second])

        await harness.model.takeOn(first.id)
        await harness.model.takeOn(second.id)

        let calls = harness.server.calls
        #expect(calls.filter { $0 == .currentUserID(Harness.url) }.count == 1)
        #expect(calls.contains(.assignTask(Harness.url, first.id, FakeDocumentServer.currentUser)))
        #expect(calls.contains(.assignTask(Harness.url, second.id, FakeDocumentServer.currentUser)))
        #expect(harness.myTasksCalls.count == 3)
        #expect(harness.events.all == ["changed", "changed"])
    }

    @Test func releaseSendsNull() async throws {
        let task = Harness.task(reason: .assigned, assignedTo: FakeDocumentServer.currentUser)
        let harness = try await loaded([task])

        await harness.model.release(task.id)

        #expect(harness.server.calls.contains(.assignTask(Harness.url, task.id, nil)))
    }

    @Test func handOverListsOnlyWhatTheServerGives() async throws {
        let task = Harness.task(reason: .addressee)
        let harness = try await loaded([task])
        let stijn = TaskAssignee(id: FakeDocumentServer.currentUser, name: "Stijn", isMe: true)
        let anne = TaskAssignee(id: Self.anne, name: "Anne", isMe: false)
        harness.server.onTaskAssignees { _, _ in [stijn, anne] }

        await harness.model.startHandOver(task.id)

        #expect(harness.model.sheet == .handOver(taskID: task.id, title: task.description, people: [anne]))
        await harness.model.handOver(task.id, to: Self.anne)
        #expect(harness.server.calls.contains(.assignTask(Harness.url, task.id, Self.anne)))
        #expect(harness.model.sheet == nil)
    }

    @Test func handOverToNobodySaysSo() async throws {
        let task = Harness.task(reason: .addressee)
        let harness = try await loaded([task])
        harness.server.onTaskAssignees { _, _ in
            [TaskAssignee(id: FakeDocumentServer.currentUser, name: "Stijn", isMe: true)]
        }

        await harness.model.startHandOver(task.id)

        #expect(harness.model.handOverEmptyText == "Er is niemand anders die deze brief mag lezen.")
    }

    @Test func handOverToSomeoneWhoCannotReadSaysSo() async throws {
        let task = Harness.task(reason: .addressee)
        let harness = try await loaded([task])
        harness.server.onAssignTask { _, _, _ in throw ServerError.other("assignee_cannot_read") }
        await harness.model.startHandOver(task.id)

        await harness.model.handOver(task.id, to: Self.anne)

        #expect(harness.model.sheetError == "Deze persoon mag de brief niet lezen. Kies iemand anders.")
        #expect(harness.model.sheet != nil)
        #expect(harness.server.calls.filter { $0 == .taskAssignees(Harness.url, task.id) }.count == 2)
    }

    @Test func aTaskSomeoneElseTookMeanwhileSaysSo() async throws {
        let task = Harness.task(reason: .unassigned)
        let harness = try await loaded([task])
        harness.server.onAssignTask { _, _, _ in throw ServerError.other("task_taken") }

        await harness.model.takeOn(task.id)

        #expect(harness.model.actionError == DocumentStrings.myTasksTaken)
        #expect(harness.myTasksCalls.count == 2)
    }

    @Test func aTaskWithoutALetterCannotBeGiven() async throws {
        let task = Harness.task(reason: .addressee)
        let harness = try await loaded([task])
        harness.server.onAssignTask { _, _, _ in throw ServerError.other("task_without_letter") }

        await harness.model.takeOn(task.id)

        #expect(harness.model.actionError == "Deze taak hoort niet bij een brief en kan niet worden gegeven.")
    }

    @Test func setDateSendsTheDayAndMovesTheTask() async throws {
        let task = Harness.task(group: .noDate, deadline: nil, daysLeft: nil)
        let harness = try await loaded([task])
        let day = CalendarDate(year: 2026, month: 12, day: 1)

        harness.model.startSettingDate(task.id)
        #expect(harness.model.sheet == .setDate(taskID: task.id, title: task.description, term: nil, current: nil))
        await harness.model.setDate(day, for: task.id)

        #expect(harness.server.calls.contains(.setTaskDeadline(Harness.url, task.id, day)))
        #expect(harness.myTasksCalls.count == 2)
        #expect(harness.model.sheet == nil)
        #expect(harness.events.all == ["changed"])
    }

    @Test func dateBeforeTheLetterIsRefusedInWords() async throws {
        let task = Harness.task(group: .noDate, deadline: nil, daysLeft: nil)
        let harness = try await loaded([task])
        harness.server.onSetTaskDeadline { _, _, _ in throw ServerError.other("validation_error") }
        harness.model.startSettingDate(task.id)

        await harness.model.setDate(CalendarDate(year: 2020, month: 1, day: 1), for: task.id)

        #expect(harness.model.sheetError == "Die datum ligt voor de datum van de brief.")
        #expect(harness.model.sheet != nil)
    }

    @Test func takeOnAVanishedTaskReloads() async throws {
        let task = Harness.task(reason: .unassigned)
        let harness = try await loaded([task])
        harness.server.onAssignTask { _, _, _ in throw ServerError.other("task_not_found") }
        harness.serve([])

        await harness.model.takeOn(task.id)

        #expect(harness.model.actionError == nil)
        #expect(harness.model.sections.isEmpty)
        #expect(harness.myTasksCalls.count == 2)
    }

    @Test func aFailedActionSaysSo() async throws {
        let task = Harness.task(reason: .assigned)
        let harness = try await loaded([task])
        harness.server.onAssignTask { _, _, _ in throw ServerError.unreachable }

        await harness.model.release(task.id)

        #expect(harness.model.actionError == DocumentStrings.changeFailed)
    }

    @Test func actionFlagsFollowReasonAndRole() async throws {
        let someoneElse = UUID()
        let unassigned = Harness.task("vrij", reason: .unassigned)
        let department = Harness.task("afdeling", reason: .department)
        let addressee = Harness.task("geadresseerd", reason: .addressee)
        let mine = Harness.task("mijn", reason: .assigned, assignedTo: FakeDocumentServer.currentUser)
        let taken = Harness.task("bij anne", reason: .other, assignedTo: someoneElse, assignedToName: "Anne")
        let letterless = Harness.task("los", reason: .unassigned, documentID: nil)
        let undated = Harness.task("geen datum", group: .noDate, deadline: nil, daysLeft: nil, reason: .addressee)
        let tasks = [unassigned, department, addressee, mine, taken, letterless, undated]
        let harness = try await loaded(tasks)

        let flags = tasks.map { task in
            row(harness, task.id).map { [$0.canTakeOn, $0.canRelease, $0.canHandOver, $0.canSetDate] } ?? []
        }
        #expect(flags == [
            [true, false, true, false], [true, false, true, false], [true, false, true, false],
            [false, true, true, false], [false, false, false, false], [false, false, false, false],
            [true, false, true, true]
        ])

        let viewer = try await loaded(tasks, canEdit: false)
        let viewerFlags = viewer.model.sections.flatMap(\.rows).map {
            [$0.canTick, $0.canTakeOn, $0.canRelease, $0.canHandOver, $0.canSetDate]
        }
        #expect(viewerFlags.allSatisfy { $0.allSatisfy { !$0 } })
    }

    @Test func someoneElsesTaskIsNotTakenOver() async throws {
        let taken = Harness.task(reason: .other, assignedTo: UUID(), assignedToName: "Anne")
        let harness = try await loaded([taken])

        await harness.model.takeOn(taken.id)
        await harness.model.release(taken.id)
        await harness.model.startHandOver(taken.id)

        #expect(!harness.server.calls.contains { if case .assignTask = $0 { true } else { false } })
        #expect(harness.model.sheet == nil)
    }

    @Test func theServersFlagsReplaceTheAppsRule() async throws {
        // An admin on a colleague's task: the server lets them hand it on and release it, not take it over.
        let colleagues = Harness.task(
            "bij een collega", reason: .other, assignedTo: UUID(), assignedToName: "Een collega",
            permissions: TaskPermissions(canTake: false, canHandOver: true, canRelease: true)
        )
        // The server says no where the app's own rule would say yes.
        let refused = Harness.task(
            "geweigerd", reason: .unassigned, permissions: TaskPermissions(canTake: false, canHandOver: false)
        )
        let harness = try await loaded([colleagues, refused])

        let flags = [colleagues, refused].map { task in
            row(harness, task.id).map { [$0.canTakeOn, $0.canRelease, $0.canHandOver] } ?? []
        }
        #expect(flags == [[false, true, true], [false, false, false]])
    }
}
