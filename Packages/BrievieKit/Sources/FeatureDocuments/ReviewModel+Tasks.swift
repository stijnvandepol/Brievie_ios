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

    /// The amount of a payment task, as typed.
    public func setAmount(_ text: String, for taskID: UUID) {
        guard let index = draft.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        draft.tasks[index].amount = text
    }

    /// Empty (unknown) or an amount Brievie can read in the user's notation.
    public func amountIsValid(for taskID: UUID) -> Bool {
        guard let task = draft.tasks.first(where: { $0.id == taskID }) else { return true }
        let text = task.amount.trimmingCharacters(in: .whitespaces)
        return text.isEmpty || TaskAmount.parse(input: text, locale: locale) != nil
    }

    /// The tasks as they go to the server: every one described, and an amount only on a payment, in the API's
    /// form. `nil` (with the reason in `saveError`) when the review cannot be confirmed yet.
    func tasksToConfirm() -> [TaskDraft]? {
        guard draft.tasks.allSatisfy({ !$0.description.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            saveError = DocumentStrings.taskNeedsDescription
            return nil
        }
        guard draft.tasks.allSatisfy({ $0.type != "pay" || amountIsValid(for: $0.id) }) else {
            saveError = DocumentStrings.amountUnreadable
            return nil
        }
        return draft.tasks.map { task in
            var task = task
            let typed = task.amount.trimmingCharacters(in: .whitespaces)
            task.amount = task.type == "pay"
                ? TaskAmount.parse(input: typed, locale: locale).map(TaskAmount.api) ?? "" : ""
            return task
        }
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

// What confirming does to the proposals not taken.
extension ReviewModel {
    /// "Er staat nog 1 voorstel open: Wonen. …" above "Bevestigen": the server dismisses every proposal the user
    /// did not take when the letter is confirmed with the lists, for good. `nil` when none is open, or when the
    /// review confirms without the lists (a 1b server: nothing is dismissed then).
    public var openProposalsNote: String? {
        guard organiseAvailable else { return nil }
        let organise = draft.organise
        let open = organise.openSuggestions(for: .addAddressee) + organise.openSuggestions(for: .addLabel)
        guard !open.isEmpty else { return nil }
        let names = open.compactMap { suggestion -> String? in
            switch suggestion.action {
            case .addAddressee: persons.first { $0.id == suggestion.targetID }?.displayName
            case .addLabel: labels.first { $0.id == suggestion.targetID }?.name
            case .unknown: nil
            }
        }.joined(separator: ", ")
        return open.count == 1
            ? String(format: DocumentStrings.openProposalsOneFormat, names)
            : String(format: DocumentStrings.openProposalsManyFormat, open.count, names)
    }
}
