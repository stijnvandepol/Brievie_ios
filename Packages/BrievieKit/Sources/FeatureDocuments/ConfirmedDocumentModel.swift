import BrievieCore
import Foundation
import Observation

/// A confirmed letter: on whose name it is and its labels change at once, open proposals are taken or dropped,
/// and its tasks are ticked off. A change shows straight away; when the server refuses it, the screen shows
/// the state before it again with a message. A viewer only reads.
@MainActor
@Observable
public final class ConfirmedDocumentModel {
    /// The server's last answer for this letter.
    public private(set) var detail: DocumentDetail
    public private(set) var persons: [Person]
    public private(set) var labels: [DocumentLabel]
    /// Members and admins change the letter; a viewer only reads.
    public let canEdit: Bool
    /// What the screen shows: the server's last answer plus the changes still on their way.
    public private(set) var organise: OrganiseDraft
    public private(set) var tasks: [ConfirmedTask]
    /// Why the last change did not work.
    public private(set) var changeError: String?
    /// Why "Nieuwe persoon" did not work.
    public private(set) var personError: String?
    /// Called after a task was ticked off or opened again (the calendar follows the open tasks).
    public var onTasksChanged: (@MainActor () -> Void)?

    private enum Change {
        case addressees(Set<UUID>)
        case labels(Set<UUID>)
        case accept(Suggestion)
        case dismiss(Suggestion)
        case task(UUID, done: Bool)
    }

    private let documents: WorkspaceDocuments
    private let onRevoked: @MainActor () -> Void
    private let onMissingPairing: @MainActor () -> Void
    /// Changes go to the server one after the other, in the order the user made them.
    @ObservationIgnored private var queue: Task<Void, Never>?
    /// Changes of addressees, labels or suggestions sent but not answered yet.
    @ObservationIgnored private var pendingOrganise = 0
    /// Task ticks sent but not answered yet.
    @ObservationIgnored private var pendingTasks = 0
    /// Whether each task is done according to the server's last answer, to go back to when a tick fails.
    @ObservationIgnored private var serverDone: [UUID: Bool]

    public init(
        detail: DocumentDetail,
        persons: [Person],
        labels: [DocumentLabel],
        documents: WorkspaceDocuments,
        canEdit: Bool,
        onRevoked: @escaping @MainActor () -> Void,
        onMissingPairing: @escaping @MainActor () -> Void
    ) {
        self.detail = detail
        self.persons = persons
        self.labels = labels
        self.documents = documents
        self.canEdit = canEdit
        self.onRevoked = onRevoked
        self.onMissingPairing = onMissingPairing
        organise = OrganiseDraft(confirmed: detail)
        tasks = detail.tasks
        serverDone = Self.doneByID(detail.tasks)
    }

    /// The workspace's persons and labels as the server has them now (loaded again with the letter).
    public func showLists(persons: [Person], labels: [DocumentLabel]) {
        self.persons = persons
        self.labels = labels
    }

    /// The letter as the server has it now (loaded again). Changes still on their way stay shown.
    public func show(_ detail: DocumentDetail) {
        self.detail = detail
        if pendingOrganise == 0 { organise = OrganiseDraft(confirmed: detail) }
        if pendingTasks == 0 {
            tasks = detail.tasks
            serverDone = Self.doneByID(detail.tasks)
        }
    }

    /// Puts the letter on exactly these names.
    public func setAddressees(_ ids: Set<UUID>) async {
        guard canEdit else { return }
        organise.setAddressees(ids)
        await send(.addressees(ids))
    }

    /// Takes the letter off one name, from what the screen shows now.
    public func removeAddressee(_ id: UUID) async {
        await setAddressees(organise.addresseeIDs.subtracting([id]))
    }

    /// Takes one label off, from what the screen shows now.
    public func removeLabel(_ id: UUID) async {
        await setLabels(organise.labelIDs.subtracting([id]))
    }

    /// Gives the letter exactly these labels.
    public func setLabels(_ ids: Set<UUID>) async {
        guard canEdit else { return }
        organise.setLabels(ids)
        await send(.labels(ids))
    }

    /// "Toevoegen": takes an open proposal.
    public func accept(_ suggestion: Suggestion) async {
        guard canEdit, suggestion.action != .unknown else { return }
        var addresseeIDs = organise.addresseeIDs
        var labelIDs = organise.labelIDs
        switch suggestion.action {
        case .addAddressee: addresseeIDs.insert(suggestion.targetID)
        case .addLabel: labelIDs.insert(suggestion.targetID)
        case .unknown: break
        }
        organise = OrganiseDraft(
            addresseeIDs: addresseeIDs, labelIDs: labelIDs, suggestions: remaining(without: suggestion)
        )
        await send(.accept(suggestion))
    }

    /// "Negeren": drops an open proposal; the letter stays as it is.
    public func dismiss(_ suggestion: Suggestion) async {
        guard canEdit else { return }
        organise = OrganiseDraft(
            addresseeIDs: organise.addresseeIDs, labelIDs: organise.labelIDs,
            suggestions: remaining(without: suggestion)
        )
        await send(.dismiss(suggestion))
    }

    /// Ticks a task off, or opens it again.
    public func setTask(_ id: UUID, done: Bool) async {
        guard canEdit, let index = tasks.firstIndex(where: { $0.id == id }), tasks[index].isDone != done else {
            return
        }
        tasks[index].isDone = done
        await send(.task(id, done: done))
    }

    /// Adds a person to the workspace and puts the letter on their name too. Returns whether it worked.
    @discardableResult
    public func createPerson(named name: String) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canEdit, !name.isEmpty else { return false }
        personError = nil
        do {
            let person = try await documents.createPerson(named: name)
            persons.append(person)
            await setAddressees(organise.addresseeIDs.union([person.id]))
            return true
        } catch .nameTaken {
            personError = DocumentStrings.nameTaken
            // Probably made in the web meanwhile: show them in the list.
            if let fresh = try? await documents.persons() { persons = fresh }
        } catch {
            handle(error) { personError = DocumentsModel.message(for: $0) }
        }
        return false
    }

    // MARK: - Private

    private func remaining(without suggestion: Suggestion) -> [Suggestion] {
        organise.suggestions.filter { $0.id != suggestion.id }
    }

    private func send(_ change: Change) async {
        changeError = nil
        if case .task = change { pendingTasks += 1 } else { pendingOrganise += 1 }
        let previous = queue
        let next = Task {
            await previous?.value
            await run(change)
        }
        queue = next
        await next.value
    }

    private func run(_ change: Change) async {
        do throws(DocumentsError) {
            switch change {
            case let .addressees(ids):
                adopt(try await documents.setAddressees(Self.sorted(ids), document: detail.summary.id))
            case let .labels(ids):
                adopt(try await documents.setLabels(Self.sorted(ids), document: detail.summary.id))
            case let .accept(suggestion):
                adopt(try await documents.acceptSuggestion(suggestion.id, document: detail.summary.id))
            case let .dismiss(suggestion):
                adopt(try await documents.dismissSuggestion(suggestion.id, document: detail.summary.id))
            case let .task(id, done):
                let answer = if done {
                    try await documents.completeTask(id)
                } else {
                    try await documents.reopenTask(id)
                }
                pendingTasks -= 1
                serverDone[id] = answer.isDone
                setDone(answer.isDone, for: id)
                onTasksChanged?()
            }
        } catch {
            switch change {
            case let .task(id, done):
                pendingTasks -= 1
                setDone(serverDone[id] ?? !done, for: id)
            case .addressees, .labels, .accept, .dismiss:
                pendingOrganise -= 1
                organise = OrganiseDraft(confirmed: detail)
            }
            handle(error) { _ in changeError = DocumentStrings.changeFailed }
        }
    }

    /// The server's answer to a change of addressees, labels or suggestions. While later changes are still on
    /// their way the screen keeps showing them; the answer to the last one shows the server's state.
    private func adopt(_ answer: DocumentDetail) {
        pendingOrganise -= 1
        detail = answer
        if pendingOrganise == 0 {
            organise = OrganiseDraft(confirmed: answer)
        }
    }

    private func setDone(_ done: Bool, for id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isDone = done
    }

    private static func doneByID(_ tasks: [ConfirmedTask]) -> [UUID: Bool] {
        Dictionary(tasks.map { ($0.id, $0.isDone) }, uniquingKeysWith: { _, last in last })
    }

    private static func sorted(_ ids: Set<UUID>) -> [UUID] {
        ids.sorted { $0.uuidString < $1.uuidString }
    }

    private func handle(_ error: DocumentsError, otherwise: (DocumentsError) -> Void) {
        switch error {
        case .revoked: onRevoked()
        case .missingPairing: onMissingPairing()
        case .cancelled: break
        default: otherwise(error)
        }
    }
}
