import BrievieCore
import Foundation

// The tasks of the draft: adding, removing (with a question) and the termijn.
extension ReviewModel {
    /// Today on the injected clock: where the termijn picker opens, and what "Datum toevoegen" fills in for the
    /// letter date.
    public var today: CalendarDate { clock.today }

    public func addTask() {
        draft.tasks.append(Self.emptyTask())
    }

    /// "Taak verwijderen": a task that holds something (a description, a termijn) is removed only after the user
    /// confirms; an empty task that was just added goes at once.
    public func requestRemoveTask(_ id: UUID) {
        guard let task = draft.tasks.first(where: { $0.id == id }) else { return }
        if task.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, task.deadline == nil {
            removeTask(id)
        } else {
            taskAskedToRemove = id
        }
    }

    /// The user confirmed the question of `requestRemoveTask(_:)`.
    public func confirmRemoveTask() {
        guard let id = taskAskedToRemove else { return }
        taskAskedToRemove = nil
        removeTask(id)
    }

    public func removeTask(_ id: UUID) {
        draft.tasks.removeAll { $0.id == id }
        if pickingDeadline == id { pickingDeadline = nil }
    }

    /// "Datum toevoegen" on a termijn opens the picker on today; the termijn stays empty until a day is chosen.
    public func startPickingDeadline(for taskID: UUID) {
        pickingDeadline = taskID
    }

    /// A day was chosen in the open picker: it becomes the termijn and the picker closes.
    public func pickDeadline(_ deadline: CalendarDate, for taskID: UUID) {
        setDeadline(deadline, for: taskID)
        if pickingDeadline == taskID { pickingDeadline = nil }
    }

    public func cancelPickingDeadline() {
        pickingDeadline = nil
    }

    /// A deadline the user changed is theirs: its source in the letter no longer belongs to it. Setting the
    /// date read from the letter again brings its source back.
    public func setDeadline(_ deadline: CalendarDate?, for taskID: UUID) {
        guard let index = draft.tasks.firstIndex(where: { $0.id == taskID }),
              draft.tasks[index].deadline != deadline
        else { return }
        draft.tasks[index].deadline = deadline
        draft.syncDeadlineSource(of: index)
    }
}
