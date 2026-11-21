import BrievieCore
import Foundation

// Who does a task of the letter: "Ik doe dit" on a task nobody has, "Niet meer aan mij" on one's own. Handing it
// to someone else and filling in a date stay in "Mijn taken" (the letter's tasks do not say for whom they are).
extension ConfirmedDocumentModel {
    /// Reads who the user is, once; until then no task is "mine" and none can be picked up.
    public func loadCurrentUser() async {
        guard canEdit, currentUserID == nil, !tasks.isEmpty else { return }
        do {
            currentUserID = try await documents.currentUserID()
        } catch {
            // An older server has no `getMe`: the buttons stay away. A 401 still ends the session.
            handle(error) { _ in }
        }
    }

    public func isMine(_ task: ConfirmedTask) -> Bool {
        guard let currentUserID else { return false }
        return task.assignedToID == currentUserID
    }

    /// "Ik doe dit": only on an open task nobody has (never someone else's), for a member or admin.
    public func canTakeOn(_ task: ConfirmedTask) -> Bool {
        canEdit && currentUserID != nil && !task.isDone && task.assignedToID == nil && task.assignedToName.isEmpty
    }

    public func canRelease(_ task: ConfirmedTask) -> Bool {
        canEdit && !task.isDone && isMine(task)
    }

    /// "Jij doet dit" or "Bij Anne"; `nil` when nobody has the task.
    public func whoDoesIt(_ task: ConfirmedTask) -> String? {
        if isMine(task) { return DocumentStrings.taskYouDoThis }
        guard !task.assignedToName.isEmpty else { return nil }
        return String(format: DocumentStrings.taskWithFormat, task.assignedToName)
    }

    public func takeOn(_ taskID: UUID) async {
        guard let task = tasks.first(where: { $0.id == taskID }), canTakeOn(task), let user = currentUserID else {
            return
        }
        await assign(taskID, to: user)
    }

    public func release(_ taskID: UUID) async {
        guard let task = tasks.first(where: { $0.id == taskID }), canRelease(task) else { return }
        await assign(taskID, to: nil)
    }

    private func assign(_ taskID: UUID, to user: UUID?) async {
        showChangeError(nil)
        do {
            let answer = try await documents.assignTask(taskID, to: user)
            setAssignee(answer.assignedToID, name: answer.assignedToName, for: taskID)
            onTasksChanged?()
        } catch {
            switch error {
            case .taskTaken:
                showChangeError(DocumentStrings.myTasksTaken)
                await reload()
            case .notFound:
                await reload()
            case .taskWithoutLetter:
                showChangeError(DocumentStrings.myTasksWithoutLetter)
            default:
                handle(error) { _ in showChangeError(DocumentStrings.changeFailed) }
            }
        }
    }

    /// Someone else changed the task meanwhile: show the letter as the server has it now.
    private func reload() async {
        if let fresh = try? await documents.detail(detail.summary.id) { show(fresh) }
    }
}
