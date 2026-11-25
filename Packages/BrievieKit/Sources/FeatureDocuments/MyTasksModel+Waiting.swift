import BrievieCore
import Foundation

/// "Wacht op reactie" and "Uitstellen" (host PR #50). Waiting is shared (whoever may tick the task off may set it);
/// snoozing is the member's own, a viewer included. The server checks every date again.
extension MyTasksModel {
    /// The server's today; the phone's own day in Amsterdam before the first answer.
    var serverToday: CalendarDate {
        answer?.today ?? CalendarDate(Date(), in: TimeZone(identifier: "Europe/Amsterdam") ?? .current)
    }

    /// After today, at most a year ahead.
    var waitRange: ClosedRange<CalendarDate> {
        serverToday.adding(days: 1)...serverToday.adding(days: 365)
    }

    /// As `waitRange`, and not past the task's date; `nil` when no day is left (the date is today or passed).
    func snoozeRange(for task: WorkspaceTask) -> ClosedRange<CalendarDate>? {
        let first = serverToday.adding(days: 1)
        let last = min(serverToday.adding(days: 365), task.deadline ?? serverToday.adding(days: 365))
        return first <= last ? first...last : nil
    }

    func canWait(_ task: WorkspaceTask, isTicked: Bool) -> Bool {
        canTick(task) && !isTicked && !task.isDone && task.documentID != nil
    }

    public func startWaiting(_ id: UUID) {
        guard let task = task(id), canWait(task, isTicked: ticked[id] ?? task.isDone) else { return }
        actionError = nil
        sheetError = nil
        sheet = .waiting(taskID: id, title: task.description, current: task.waitingUntil, range: waitRange)
    }

    public func startSnoozing(_ id: UUID) {
        guard let task = task(id), let range = snoozeRange(for: task) else { return }
        actionError = nil
        sheetError = nil
        sheet = .snooze(taskID: id, title: task.description, current: task.snoozedUntil, range: range)
    }

    /// Waits for a reply until `until`; `nil` stops waiting. The task moves to the group the server gives it.
    public func setWaiting(_ until: CalendarDate?, for id: UUID) async {
        await change(id) { documents, id throws(DocumentsError) in
            _ = try await documents.setTaskWaiting(id, until: until)
        }
    }

    /// Snoozes the task in the member's own list until `until`; `nil` brings it back.
    public func snooze(_ until: CalendarDate?, for id: UUID) async {
        await change(id) { documents, id throws(DocumentsError) in
            _ = try await documents.snoozeTask(id, until: until)
        }
    }

    private func change(
        _ id: UUID, _ call: (WorkspaceDocuments, UUID) async throws(DocumentsError) -> Void
    ) async {
        sheetError = nil
        actionError = nil
        do {
            try await call(documents, id)
            sheet = nil
            onTasksChanged()
            await load()
        } catch {
            switch error {
            case .invalid: sheetError = DocumentStrings.errorDateRange
            case .snoozeAfterDeadline: sheetError = DocumentStrings.errorSnoozeAfterDeadline
            case .taskDone: sheetError = DocumentStrings.errorTaskDone
            default:
                sheet = nil
                handle(error) { error in actionError = DocumentsModel.message(for: error) }
            }
        }
    }
}
