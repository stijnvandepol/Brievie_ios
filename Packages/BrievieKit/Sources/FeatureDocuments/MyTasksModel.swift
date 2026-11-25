import BrievieCore
import Foundation
import Observation

/// "Mijn taken": the member's open tasks from their own post by date, the ones nobody has picked up yet (in an
/// organisation), and what they ticked off in the last 30 days. The server decides every task, group, reason and
/// day count; this model only orders the groups and puts them into words.
///
/// It depends on nothing but `WorkspaceDocuments`, the role and closures, so the same model can serve the title
/// menu entry now and a "Taken" tab later.
@MainActor
@Observable
public final class MyTasksModel {
    public enum State: Equatable, Sendable {
        case loading
        case loaded
        case failed(message: String)
        /// The server is older than "Mijn taken".
        case notSupported
    }

    public enum Filter: Equatable, Sendable {
        case mine
        case all
    }

    public enum Tab: Equatable, Sendable {
        case open
        case done
    }

    public private(set) var state: State = .loading
    public private(set) var filter: Filter = .mine
    public private(set) var tab: Tab = .open
    /// Why an action did not work; the list stays.
    public internal(set) var actionError: String?
    /// For VoiceOver after a tick: "Afgevinkt: …" / "Weer open: …".
    public private(set) var announcement: String?
    /// Members and admins tick tasks off; a viewer only reads.
    public let canEdit: Bool

    let documents: WorkspaceDocuments
    let locale: Locale
    let onTasksChanged: @MainActor () -> Void
    let onShowInbox: @MainActor () -> Void
    let onRevoked: @MainActor () -> Void
    let onMissingPairing: @MainActor () -> Void

    var openTasks: [WorkspaceTask] = []
    var pickUpTasks: [WorkspaceTask] = []
    var doneTasks: [WorkspaceTask] = []
    var answer: MyTasks?
    /// Ticks the user made on this screen: the row stays where it is (struck through) until a reload.
    var ticked: [UUID: Bool] = [:]
    /// Whether each task is done by the server's last answer, to go back to when a tick fails.
    @ObservationIgnored var serverDone: [UUID: Bool] = [:]
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var loads = 0
    /// The signed-in user's id, read once for "Ik doe dit".
    @ObservationIgnored var currentUserID: UUID?
    /// The hand-over or date sheet that is open.
    public var sheet: Sheet?
    /// Why the change in the open sheet did not work.
    public internal(set) var sheetError: String?

    /// - Parameters:
    ///   - canEdit: the role may change tasks (not a viewer).
    ///   - onTasksChanged: a task changed on the server (counts, reminders and the calendar follow).
    ///   - onShowInbox: "Naar Inbox" under the waiting letters.
    public init(
        documents: WorkspaceDocuments,
        canEdit: Bool,
        locale: Locale = .autoupdatingCurrent,
        onTasksChanged: @escaping @MainActor () -> Void,
        onShowInbox: @escaping @MainActor () -> Void,
        onRevoked: @escaping @MainActor () -> Void,
        onMissingPairing: @escaping @MainActor () -> Void
    ) {
        self.documents = documents
        self.canEdit = canEdit
        self.locale = locale
        self.onTasksChanged = onTasksChanged
        self.onShowInbox = onShowInbox
        self.onRevoked = onRevoked
        self.onMissingPairing = onMissingPairing
    }

    // MARK: - What the screen shows

    /// The open tasks in the server's groups, in the order Te laat, Binnen 7 dagen, Later, Zonder datum.
    public var sections: [Section] {
        let rows = openTasks.map(row(for:))
        let groups: [TaskGroup] = [.overdue, .withinWeek, .later, .noDate]
        return groups.compactMap { group in
            let members = zip(openTasks, rows).filter { Self.group(of: $0.0) == group }.map(\.1)
            guard !members.isEmpty, let title = TaskWords.groupTitle(group) else { return nil }
            return Section(group: group, title: title, rows: members)
        }
    }

    /// "Wacht op reactie (n)" and "Uitgesteld (n)" (host PR #50): below the groups, collapsed by the screen.
    public var parkedSections: [Section] {
        guard tab == .open else { return [] }
        return [TaskGroup.waiting, .snoozed].compactMap { group in
            let members = openTasks.filter { $0.group == group }.map(row(for:))
            guard !members.isEmpty, let title = TaskWords.groupTitle(group) else { return nil }
            return Section(group: group, title: title, rows: members)
        }
    }

    /// "Op te pakken": only in an organisation, on the own list.
    public var toPickUp: Section? {
        guard answer?.split == true, filter == .mine, tab == .open else { return nil }
        return Section(group: nil, title: DocumentStrings.myTasksToPickUp, rows: pickUpTasks.map(row(for:)))
    }

    public var toPickUpEmptyText: String? {
        toPickUp?.rows.isEmpty == true ? DocumentStrings.myTasksToPickUpEmpty : nil
    }

    /// The ticked-off tasks of the last 30 days.
    public var doneRows: [Row] { doneTasks.map(row(for:)) }

    public var description: String {
        answer?.split == true ? DocumentStrings.myTasksDescriptionBusiness : DocumentStrings.myTasksDescriptionHome
    }

    public var waitingLine: String? {
        guard let waiting = answer?.waitingLetters, waiting > 0, tab == .open else { return nil }
        return DocumentStrings.myTasksWaiting(waiting)
    }

    public var noPersonNotice: String? {
        answer?.hasPerson == false && filter == .mine ? DocumentStrings.myTasksNoPerson : nil
    }

    public var viewerNotice: String? { canEdit ? nil : DocumentStrings.myTasksViewer }

    public var truncatedNote: String? { answer?.truncated == true ? DocumentStrings.myTasksTruncated : nil }

    public var emptyText: String? {
        guard state == .loaded else { return nil }
        switch tab {
        case .open: return openTasks.isEmpty ? DocumentStrings.myTasksEmptyOpen : nil
        case .done: return doneTasks.isEmpty ? DocumentStrings.myTasksEmptyDone : nil
        }
    }

    // MARK: - Loading

    /// Loads the chosen tab and filter. A list on screen stays when a reload fails; ticked rows leave (the server
    /// no longer lists them as open).
    public func load() async {
        loads += 1
        let load = loads
        let part: MyTasksPart = filter == .mine ? .mine : .all
        let tab = tab
        let filter = filter
        do {
            let main = try await documents.myTasks(
                part: part, status: tab == .open ? .open : .done, includeWaiting: tab == .open
            )
            var pickUp: [WorkspaceTask] = []
            if tab == .open, main.split, filter == .mine {
                pickUp = try await documents.myTasks(part: .toPickUp, status: .open).items
            }
            guard load == loads else { return }
            answer = main
            switch tab {
            case .open:
                openTasks = main.items
                pickUpTasks = pickUp
            case .done:
                doneTasks = main.items
            }
            ticked = [:]
            serverDone = [:]
            state = .loaded
        } catch {
            guard load == loads else { return }
            if error == .notSupported {
                state = .notSupported
                return
            }
            handle(error) { error in
                if state == .loaded {
                    actionError = DocumentsModel.message(for: error)
                } else {
                    state = .failed(message: DocumentsModel.message(for: error))
                }
            }
        }
    }

    public func select(_ filter: Filter) async {
        guard filter != self.filter else { return }
        self.filter = filter
        actionError = nil
        await load()
    }

    public func select(_ tab: Tab) async {
        guard tab != self.tab else { return }
        self.tab = tab
        actionError = nil
        await load()
    }

    /// "Naar Inbox".
    public func showInbox() {
        onShowInbox()
    }

    /// The screen went away: rows ticked here leave the lists, as a refresh would do.
    public func leave() {
        // A row whose state differs from what the list was loaded with no longer belongs on this list.
        let changed = Set(ticked.filter { id, done in done != task(id)?.isDone }.keys)
        openTasks.removeAll { changed.contains($0.id) }
        pickUpTasks.removeAll { changed.contains($0.id) }
        doneTasks.removeAll { changed.contains($0.id) }
        ticked = [:]
        announcement = nil
    }

    // MARK: - Ticking

    /// Ticks a task off (or opens it again with `false`): at once on screen, then on the server, in order.
    public func setDone(_ done: Bool, for id: UUID) async {
        guard let task = task(id), canTick(task) else { return }
        actionError = nil
        if serverDone[id] == nil { serverDone[id] = task.isDone }
        ticked[id] = done
        let format = done ? DocumentStrings.myTasksAnnounceDoneFormat : DocumentStrings.myTasksAnnounceOpenFormat
        announcement = String(format: format, task.description)
        await enqueue { [weak self] in await self?.send(done, for: id) }
    }

    private func send(_ done: Bool, for id: UUID) async {
        do {
            let answer = done ? try await documents.completeTask(id) : try await documents.reopenTask(id)
            serverDone[id] = answer.isDone
            onTasksChanged()
        } catch {
            if error == .notFound {
                await vanished(id)
                return
            }
            ticked[id] = serverDone[id]
            handle(error) { _ in actionError = DocumentStrings.changeFailed }
        }
    }

    // MARK: - Shared with the actions

    func task(_ id: UUID) -> WorkspaceTask? {
        (openTasks + pickUpTasks + doneTasks).first { $0.id == id }
    }

    /// The task is gone meanwhile (ticked or released elsewhere, the letter trashed, sight lost): the row leaves
    /// quietly and the list loads again.
    func vanished(_ id: UUID) async {
        openTasks.removeAll { $0.id == id }
        pickUpTasks.removeAll { $0.id == id }
        doneTasks.removeAll { $0.id == id }
        ticked[id] = nil
        await load()
    }

    func canTick(_ task: WorkspaceTask) -> Bool {
        canEdit && task.canEdit != false
    }

    func handle(_ error: DocumentsError, otherwise: (DocumentsError) -> Void) {
        switch error {
        case .revoked: onRevoked()
        case .missingPairing: onMissingPairing()
        case .cancelled: break
        default: otherwise(error)
        }
    }

    // MARK: - Private

    private func enqueue(_ work: @escaping @MainActor () async -> Void) async {
        let previous = queue
        let next = Task { @MainActor in
            await previous?.value
            await work()
        }
        queue = next
        await next.value
    }

    private func row(for task: WorkspaceTask) -> Row {
        let myName = documents.userName
        let isTicked = ticked[task.id] ?? task.isDone
        let flags = actionFlags(for: task, isTicked: isTicked)
        return Row(
            id: task.id, documentID: task.documentID, title: task.description, typeWord: TaskWords.typeWord(task),
            when: TaskWords.when(task, locale: locale), isLate: TaskWords.isLate(task),
            amount: TaskWords.amount(task, locale: locale),
            fromFor: TaskWords.fromFor(task, me: myName, locale: locale),
            why: TaskWords.why(task), needsDate: TaskWords.needsDate(task),
            doneLine: TaskWords.doneLine(task, locale: locale), isTicked: isTicked, canTick: canTick(task),
            canTakeOn: flags.takeOn, canRelease: flags.release, canHandOver: flags.handOver,
            canSetDate: flags.setDate, parkedLine: TaskWords.parkedLine(task, locale: locale),
            canWait: canWait(task, isTicked: isTicked), isWaiting: task.waitingUntil != nil,
            canSnooze: !isTicked && !task.isDone && snoozeRange(for: task) != nil,
            isSnoozed: task.snoozedUntil != nil, tickLabel: TaskWords.tickLabel(task),
            accessibilityLabel: TaskWords.accessibilityLabel(task, me: myName, locale: locale)
        )
    }

    /// The server's group; a group this app does not know goes by whether the task has a date (never dropped).
    private static func group(of task: WorkspaceTask) -> TaskGroup {
        switch task.group {
        case .overdue, .withinWeek, .later, .noDate, .waiting, .snoozed: task.group
        case .none, .unknown: task.deadline == nil ? .noDate : .later
        }
    }
}

extension MyTasksModel {
    /// One task as the screen shows it.
    public struct Row: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let documentID: UUID?
        /// What to do: the task's description.
        public let title: String
        public let typeWord: String?
        public let when: String?
        /// Past the deadline: shown in the warning colour, and `when` says it in words.
        public let isLate: Bool
        public let amount: String?
        public let fromFor: String?
        public let why: String?
        /// "De brief noemt een termijn: ‘…’. Vul de datum in."; `nil` when the task has its date.
        public let needsDate: String?
        public let doneLine: String?
        /// Ticked off: struck through on the open list, the normal state on the done list.
        public let isTicked: Bool
        public let canTick: Bool
        public let canTakeOn: Bool
        public let canRelease: Bool
        public let canHandOver: Bool
        public let canSetDate: Bool
        /// "Wacht op reactie tot 3 dec", "Wachten voorbij sinds 3 dec", "Uitgesteld tot 1 dec".
        public let parkedLine: String?
        public let canWait: Bool
        public let isWaiting: Bool
        public let canSnooze: Bool
        public let isSnoozed: Bool
        public let tickLabel: String
        public let accessibilityLabel: String
    }

    public struct Section: Identifiable, Equatable, Sendable {
        /// `nil` for "Op te pakken".
        public let group: TaskGroup?
        public let title: String
        public let rows: [Row]

        public var id: String { group?.rawValue ?? "to_pick_up" }
        public var count: Int { rows.count }
        /// "Te laat (2)".
        public var header: String { "\(title) (\(count))" }
    }

    /// What a row offers besides ticking.
    struct ActionFlags: Equatable {
        var takeOn = false
        var release = false
        var handOver = false
        var setDate = false
    }
}
