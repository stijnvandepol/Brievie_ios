import BrievieCore
import Foundation

/// "Ik doe dit", "Niet meer aan mij", "Geef aan…" and "Datum invullen". The server decides who may do what and
/// where the task goes next: after every change the list loads again.
extension MyTasksModel {
    public enum Sheet: Identifiable, Equatable, Sendable {
        /// The members who may read the task's letter, without the member themselves.
        case handOver(taskID: UUID, title: String, people: [TaskAssignee])
        /// The term the letter names, and the date the task has now.
        case setDate(taskID: UUID, title: String, term: String?, current: CalendarDate?)
        /// "Wacht op reactie…" and "Uitstellen…": the date the task has now, and the days that may be chosen.
        case waiting(taskID: UUID, title: String, current: CalendarDate?, range: ClosedRange<CalendarDate>)
        case snooze(taskID: UUID, title: String, current: CalendarDate?, range: ClosedRange<CalendarDate>)

        public var id: String {
            switch self {
            case let .handOver(taskID, _, _): "handOver-\(taskID)"
            case let .setDate(taskID, _, _, _): "setDate-\(taskID)"
            case let .waiting(taskID, _, _, _): "waiting-\(taskID)"
            case let .snooze(taskID, _, _, _): "snooze-\(taskID)"
            }
        }
    }

    /// Under the names when nobody else may read the letter.
    public var handOverEmptyText: String? {
        guard case let .handOver(_, _, people) = sheet, people.isEmpty else { return nil }
        return DocumentStrings.myTasksHandOverNobody
    }

    /// "Ik doe dit": the task becomes the member's own.
    public func takeOn(_ id: UUID) async {
        guard let task = task(id), actionFlags(for: task, isTicked: ticked[id] ?? task.isDone).takeOn else { return }
        actionError = nil
        do {
            let user = try await myUserID()
            _ = try await documents.assignTask(id, to: user)
            await changed()
        } catch {
            await failed(error, for: id)
        }
    }

    /// "Niet meer aan mij": the task goes back to whoever it is for.
    public func release(_ id: UUID) async {
        guard let task = task(id), actionFlags(for: task, isTicked: ticked[id] ?? task.isDone).release else { return }
        actionError = nil
        do {
            _ = try await documents.assignTask(id, to: nil)
            await changed()
        } catch {
            await failed(error, for: id)
        }
    }

    /// "Geef aan…": opens the list of who may read the letter (exactly what the server gives, names only).
    public func startHandOver(_ id: UUID) async {
        guard let task = task(id), actionFlags(for: task, isTicked: ticked[id] ?? task.isDone).handOver else { return }
        actionError = nil
        sheetError = nil
        do {
            let people = try await documents.taskAssignees(id).filter { !$0.isMe }
            sheet = .handOver(taskID: id, title: task.description, people: people)
        } catch {
            await failed(error, for: id)
        }
    }

    public func handOver(_ id: UUID, to user: UUID) async {
        sheetError = nil
        do {
            _ = try await documents.assignTask(id, to: user)
            sheet = nil
            await changed()
        } catch {
            switch error {
            case .assigneeCannotRead:
                sheetError = DocumentStrings.myTasksCannotRead
                if let people = try? await documents.taskAssignees(id).filter({ !$0.isMe }),
                   case let .handOver(taskID, title, _) = sheet, taskID == id {
                    sheet = .handOver(taskID: taskID, title: title, people: people)
                }
            default:
                await failed(error, for: id, inSheet: true)
            }
        }
    }

    /// "Datum invullen": opens the date sheet with the letter's term above it.
    public func startSettingDate(_ id: UUID) {
        guard let task = task(id), actionFlags(for: task, isTicked: ticked[id] ?? task.isDone).setDate else { return }
        actionError = nil
        sheetError = nil
        sheet = .setDate(
            taskID: id, title: task.description, term: task.termQuote.isEmpty ? nil : task.termQuote,
            current: task.deadline
        )
    }

    /// Saves the date (or with `nil` takes it away); the task moves to the group the server gives it.
    public func setDate(_ date: CalendarDate?, for id: UUID) async {
        sheetError = nil
        do {
            _ = try await documents.setTaskDeadline(id, to: date)
            sheet = nil
            await changed()
        } catch {
            if error == .invalid {
                sheetError = DocumentStrings.myTasksDateBeforeLetter
            } else {
                await failed(error, for: id, inSheet: true)
            }
        }
    }

    public func closeSheet() {
        sheet = nil
        sheetError = nil
    }

    /// What a row offers besides ticking. Against the owner's rule a task someone else has cannot be taken over,
    /// handed on or released from here. When the server sends `can_take` / `can_hand_over` / `can_release`,
    /// those replace this rule.
    func actionFlags(for task: WorkspaceTask, isTicked: Bool) -> ActionFlags {
        guard canTick(task), !isTicked else { return ActionFlags() }
        // The server's own rule (host PR #44) wins; the app's rule below is for an older server.
        if let permissions = task.permissions {
            return ActionFlags(
                takeOn: permissions.canTake, release: permissions.canRelease, handOver: permissions.canHandOver,
                setDate: task.deadline == nil
            )
        }
        let hasLetter = task.documentID != nil
        let nobodyHasIt = task.assignedToID == nil && task.assignedToName.isEmpty
        let mine = task.reason == .assigned
        let forMe: Set<TaskReason> = [.addressee, .department, .unassigned, .other]
        return ActionFlags(
            takeOn: hasLetter && nobodyHasIt && forMe.contains(task.reason),
            release: mine,
            handOver: hasLetter && (nobodyHasIt || mine),
            setDate: task.deadline == nil
        )
    }

    // MARK: - Private

    private func myUserID() async throws(DocumentsError) -> UUID {
        if let currentUserID { return currentUserID }
        let id = try await documents.currentUserID()
        currentUserID = id
        return id
    }

    private func changed() async {
        onTasksChanged()
        await load()
    }

    private func failed(_ error: DocumentsError, for id: UUID, inSheet: Bool = false) async {
        switch error {
        case .notFound:
            closeSheet()
            await vanished(id)
        case .taskWithoutLetter:
            show(DocumentStrings.myTasksWithoutLetter, inSheet: inSheet)
        case .taskTaken:
            closeSheet()
            actionError = DocumentStrings.myTasksTaken
            await load()
        default:
            handle(error) { _ in show(DocumentStrings.changeFailed, inSheet: inSheet) }
        }
    }

    private func show(_ message: String, inSheet: Bool) {
        if inSheet { sheetError = message } else { actionError = message }
    }
}
