import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// A task's termijn and removing a task: nothing is set or lost by a tap that only looks (simulator, 20-11-2026:
/// "Datum toevoegen" filled in today, and "Taak verwijderen" removed a task with a termijn without asking).
@MainActor
@Suite struct ReviewTaskEditTests {
    private let harness = ReviewHarness()

    private func loadedModelWithNewTask() async throws -> (ReviewModel, UUID) {
        let model = try harness.model()
        await model.load()
        model.addTask()
        return (model, try #require(model.draft.tasks.last).id)
    }

    // MARK: - Termijn

    @Test func openingTheTermijnPickerStoresNothing() async throws {
        let (model, task) = try await loadedModelWithNewTask()

        model.startPickingDeadline(for: task)

        #expect(model.pickingDeadline == task)
        #expect(model.draft.tasks.last?.deadline == nil)
    }

    @Test func thePickerStartsOnTodayOfTheInjectedClock() async throws {
        let (model, _) = try await loadedModelWithNewTask()

        #expect(model.today == CalendarDate(year: 2026, month: 11, day: 19))
    }

    @Test func confirmingAfterOnlyLookingSendsNoTermijn() async throws {
        let (model, task) = try await loadedModelWithNewTask()
        model.draft.tasks[model.draft.tasks.count - 1].description = "Bellen"
        model.startPickingDeadline(for: task)
        harness.server.onConfirm { _, id, _ in DocumentFixtures.detail(id: id, status: .done) }

        await model.confirm()

        let sent = harness.server.calls.compactMap { call -> ConfirmedReview? in
            if case let .confirm(_, _, review) = call { return review }
            return nil
        }
        #expect(try #require(sent.first).tasks.last?.deadline == nil)
    }

    @Test func choosingADayStoresItAndClosesThePicker() async throws {
        let (model, task) = try await loadedModelWithNewTask()
        model.startPickingDeadline(for: task)

        model.pickDeadline(CalendarDate(year: 2027, month: 1, day: 1), for: task)

        #expect(model.draft.tasks.last?.deadline == CalendarDate(year: 2027, month: 1, day: 1))
        #expect(model.draft.tasks.last?.deadlineSource == "manual")
        #expect(model.pickingDeadline == nil)
    }

    @Test func cancellingLeavesTheTermijnEmpty() async throws {
        let (model, task) = try await loadedModelWithNewTask()
        model.startPickingDeadline(for: task)

        model.cancelPickingDeadline()

        #expect(model.pickingDeadline == nil)
        #expect(model.draft.tasks.last?.deadline == nil)
    }

    // MARK: - Removing a task

    @Test func removingATaskWithContentAsksFirst() async throws {
        let model = try harness.model()
        await model.load()
        let task = try #require(model.draft.tasks.first)

        model.requestRemoveTask(task.id)

        #expect(model.taskAskedToRemove == task.id)
        #expect(model.draft.tasks.contains { $0.id == task.id })
    }

    @Test func confirmingTheQuestionRemovesTheTask() async throws {
        let model = try harness.model()
        await model.load()
        let task = try #require(model.draft.tasks.first)
        model.requestRemoveTask(task.id)

        model.confirmRemoveTask()

        #expect(!model.draft.tasks.contains { $0.id == task.id })
        #expect(model.taskAskedToRemove == nil)
    }

    @Test func keepingTheTaskChangesNothing() async throws {
        let model = try harness.model()
        await model.load()
        let before = model.draft
        let task = try #require(model.draft.tasks.first)
        model.requestRemoveTask(task.id)

        model.taskAskedToRemove = nil
        model.confirmRemoveTask()

        #expect(model.draft == before)
    }

    @Test func anEmptyNewTaskGoesWithoutAQuestion() async throws {
        let (model, task) = try await loadedModelWithNewTask()

        model.requestRemoveTask(task)

        #expect(model.taskAskedToRemove == nil)
        #expect(!model.draft.tasks.contains { $0.id == task })
    }

    @Test func theQuestionClosesWhenTheAppLeavesTheForeground() async throws {
        let model = try harness.model()
        await model.load()
        model.requestRemoveTask(try #require(model.draft.tasks.first).id)

        model.sceneDidChange(isActive: false)

        #expect(model.taskAskedToRemove == nil)
        #expect(model.draft.tasks.count == 1)
    }
}
