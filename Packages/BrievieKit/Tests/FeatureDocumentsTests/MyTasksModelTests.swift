import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// "Mijn taken": the server's groups in order, "Op te pakken" in an organisation, ticking off with undo, Afgerond,
/// and every notice the screen shows.
@MainActor
@Suite struct MyTasksModelTests {
    private typealias Harness = MyTasksHarness

    @Test func loadsMineOpenAndGroupsInOrder() async throws {
        let harness = try Harness()
        harness.serve([
            Harness.task("a", group: .later), Harness.task("b", group: .overdue, daysLeft: -2),
            Harness.task("c", group: .noDate, deadline: nil, daysLeft: nil), Harness.task("d", group: .withinWeek),
            Harness.task("e", group: .overdue, daysLeft: -1)
        ])

        await harness.model.load()

        let sections = harness.model.sections
        #expect(sections.map(\.group) == [.overdue, .withinWeek, .later, .noDate])
        #expect(sections.map(\.count) == [2, 1, 1, 1])
        #expect(sections[0].rows.map(\.title) == ["b", "e"])
        #expect(sections[0].header == "Te laat (2)")
        #expect(sections[0].rows.allSatisfy { $0.isLate })
        #expect(harness.myTasksCalls == [.myTasks(Harness.url, .mine, .open)])
        #expect(harness.model.state == .loaded)
    }

    @Test func aGroupThisAppDoesNotKnowIsNeverDropped() async throws {
        let harness = try Harness()
        harness.serve([
            Harness.task("dated", group: .unknown), Harness.task("undated", group: .none, deadline: nil, daysLeft: nil)
        ])

        await harness.model.load()

        #expect(harness.model.sections.map(\.group) == [.later, .noDate])
    }

    @Test func toPickUpOnlyForAnOrganisation() async throws {
        let home = try Harness()
        home.serve([Harness.task()], pickUp: [Harness.task("x", reason: .unassigned)], split: false)
        await home.model.load()
        #expect(home.model.toPickUp == nil)
        #expect(!home.myTasksCalls.contains(.myTasks(Harness.url, .toPickUp, .open)))
        #expect(home.model.description == DocumentStrings.myTasksDescriptionHome)

        let business = try Harness()
        business.serve([Harness.task()], split: true)
        await business.model.load()
        #expect(business.model.toPickUp?.title == "Op te pakken")
        #expect(business.model.toPickUp?.rows.isEmpty == true)
        #expect(business.model.toPickUpEmptyText == "Er ligt niets op te pakken.")
        #expect(business.myTasksCalls == [
            .myTasks(Harness.url, .mine, .open), .myTasks(Harness.url, .toPickUp, .open)
        ])
        #expect(business.model.description == DocumentStrings.myTasksDescriptionBusiness)
    }

    @Test func allTasksFilterAsksForAllAndHidesToPickUp() async throws {
        let harness = try Harness()
        harness.serve([Harness.task()], split: true)
        await harness.model.load()

        await harness.model.select(.all)

        #expect(harness.myTasksCalls.last == .myTasks(Harness.url, .all, .open))
        #expect(harness.model.toPickUp == nil)
    }

    @Test func doneTabListsTickedOffWithWho() async throws {
        let harness = try Harness()
        let noon = CalendarDate(year: 2026, month: 11, day: 20).date(in: .current)
        harness.serve([], done: [Harness.task(done: true, completedBy: "Anne", completedAt: noon)])

        await harness.model.select(.done)

        #expect(harness.myTasksCalls == [.myTasks(Harness.url, .mine, .done)])
        #expect(harness.model.doneRows.first?.doneLine == "Afgevinkt door Anne op 20 nov")
        #expect(harness.model.doneRows.first?.isTicked == true)
    }

    @Test func tickKeepsTheRowStruckAndUndoReopens() async throws {
        let harness = try Harness()
        let task = Harness.task()
        harness.serve([task])
        await harness.model.load()

        await harness.model.setDone(true, for: task.id)

        #expect(harness.model.sections.first?.rows.first?.isTicked == true)
        #expect(harness.server.calls.contains(.completeTask(Harness.url, task.id)))
        #expect(harness.events.all == ["changed"])
        #expect(harness.model.announcement == "Afgevinkt: Betaal de aanslag")

        await harness.model.setDone(false, for: task.id)

        #expect(harness.server.calls.contains(.reopenTask(Harness.url, task.id)))
        #expect(harness.model.sections.first?.rows.first?.isTicked == false)
        #expect(harness.model.announcement == "Weer open: Betaal de aanslag")
    }

    @Test func refreshDropsStruckRows() async throws {
        let harness = try Harness()
        let task = Harness.task()
        harness.serve([task])
        await harness.model.load()
        await harness.model.setDone(true, for: task.id)

        harness.serve([])
        await harness.model.load()

        #expect(harness.model.sections.isEmpty)
    }

    @Test func leavingTheScreenDropsStruckRows() async throws {
        let harness = try Harness()
        let ticked = Harness.task("weg")
        let kept = Harness.task("blijft")
        harness.serve([ticked, kept])
        await harness.model.load()
        await harness.model.setDone(true, for: ticked.id)

        harness.model.leave()

        #expect(harness.model.sections.flatMap(\.rows).map(\.title) == ["blijft"])
    }

    @Test func failedTickFlipsBack() async throws {
        let harness = try Harness()
        let task = Harness.task()
        harness.serve([task])
        harness.server.onCompleteTask { _, _ in throw ServerError.unreachable }
        await harness.model.load()

        await harness.model.setDone(true, for: task.id)

        #expect(harness.model.sections.first?.rows.first?.isTicked == false)
        #expect(harness.model.actionError == DocumentStrings.changeFailed)
        #expect(harness.events.all.isEmpty)
    }

    @Test func tickOnAVanishedTaskRemovesTheRow() async throws {
        let harness = try Harness()
        let task = Harness.task()
        harness.serve([task])
        harness.server.onCompleteTask { _, _ in throw ServerError.other("task_not_found") }
        await harness.model.load()
        harness.serve([])

        await harness.model.setDone(true, for: task.id)

        #expect(harness.model.sections.isEmpty)
        #expect(harness.model.actionError == nil)
        #expect(harness.myTasksCalls.count == 2)
    }

    @Test func viewerGetsNoActions() async throws {
        let viewer = try Harness(canEdit: false)
        viewer.serve([Harness.task()])
        await viewer.model.load()
        #expect(viewer.model.sections.flatMap(\.rows).allSatisfy { !$0.canTick })
        #expect(viewer.model.viewerNotice == "Je kunt taken bekijken, maar niet afvinken.")
        let id = try #require(viewer.model.sections.first?.rows.first?.id)
        await viewer.model.setDone(true, for: id)
        #expect(!viewer.server.calls.contains(.completeTask(Harness.url, id)))

        let member = try Harness()
        member.serve([
            Harness.task("nee", canEdit: false), Harness.task("ja", canEdit: true), Harness.task("oud", canEdit: nil)
        ])
        await member.model.load()
        #expect(member.model.sections.flatMap(\.rows).map(\.canTick) == [false, true, true])
        #expect(member.model.viewerNotice == nil)
    }

    @Test func memberWithoutPersonIsTold() async throws {
        let harness = try Harness()
        harness.serve([], hasPerson: false)
        await harness.model.load()
        #expect(harness.model.noPersonNotice == DocumentStrings.myTasksNoPerson)
        #expect(harness.model.noPersonNotice?.hasPrefix("Je account hangt nog niet aan een naam.") == true)

        await harness.model.select(.all)

        #expect(harness.model.noPersonNotice == nil)
    }

    @Test func waitingLettersLineLinksToTheInbox() async throws {
        let harness = try Harness()
        harness.serve([], waiting: 3)
        await harness.model.load()
        #expect(harness.model.waitingLine
            == "Er wachten nog 3 brieven op nakijken. Daar kunnen nieuwe taken uit komen.")

        harness.model.showInbox()
        #expect(harness.events.all == ["inbox"])

        harness.serve([], waiting: 1)
        await harness.model.load()
        #expect(harness.model.waitingLine == "Er wacht nog 1 brief op nakijken. Daar kunnen nieuwe taken uit komen.")

        harness.serve([], waiting: 0)
        await harness.model.load()
        #expect(harness.model.waitingLine == nil)
    }

    @Test func truncatedListSaysSo() async throws {
        let harness = try Harness()
        harness.serve([Harness.task()], truncated: true)

        await harness.model.load()

        #expect(harness.model.truncatedNote == "Alleen de eerste 500 taken worden getoond.")
    }

    @Test func emptyOpenListExplainsItself() async throws {
        let harness = try Harness()
        harness.serve([])
        #expect(harness.model.emptyText == nil)

        await harness.model.load()
        #expect(harness.model.emptyText == DocumentStrings.myTasksEmptyOpen)

        await harness.model.select(.done)
        #expect(harness.model.emptyText == "Je hebt de laatste 30 dagen niets afgevinkt.")
    }

    @Test func olderServerIsNotSupported() async throws {
        let harness = try Harness()
        harness.server.onMyTasks { _, _, _ in throw ServerError.other("http_404") }

        await harness.model.load()

        #expect(harness.model.state == .notSupported)
    }

    @Test func failedFirstLoadSaysWhy() async throws {
        let harness = try Harness()
        harness.server.onMyTasks { _, _, _ in throw ServerError.unreachable }

        await harness.model.load()

        #expect(harness.model.state == .failed(message: DocumentStrings.unreachable))
    }

    @Test func failedReloadKeepsTheList() async throws {
        let harness = try Harness()
        harness.serve([Harness.task()])
        await harness.model.load()
        harness.server.onMyTasks { _, _, _ in throw ServerError.unreachable }

        await harness.model.load()

        #expect(harness.model.state == .loaded)
        #expect(harness.model.sections.count == 1)
        #expect(harness.model.actionError == DocumentStrings.unreachable)
    }

    @Test func aRevokedDeviceEndsTheSession() async throws {
        let harness = try Harness()
        harness.server.onMyTasks { _, _, _ in throw ServerError.unauthorized }

        await harness.model.load()

        #expect(harness.events.all == ["revoked"])
    }

    @Test func aStaleAnswerNeverOverwritesANewerOne() async throws {
        let inner = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
        let gated = GatedDocumentServer(inner)
        let harness = try Harness(server: inner, gated: gated)
        inner.onMyTasks { _, part, _ in
            MyTasks(items: [Harness.task(part == .mine ? "mijn" : "alles")], today: Harness.today)
        }
        gated.close(gate: .myTasks(.mine))
        let first = Task { await harness.model.load() }
        while !gated.isWaiting(gate: .myTasks(.mine)) { await Task.yield() }

        await harness.model.select(.all)
        gated.open(gate: .myTasks(.mine))
        await first.value

        #expect(harness.model.sections.flatMap(\.rows).map(\.title) == ["alles"])
    }
}
