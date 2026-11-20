import BrievieCore
import Foundation
import Synchronization

/// A `FakeDocumentServer` whose list for a chosen person or inbox state waits until the test opens its gate, to
/// play out a slow answer for a scope the user has already left. Task ticks can be held the same way.
final class GatedDocumentServer: DocumentServer {
    /// A list that can be held: the one of a person, or one inbox state's.
    enum Gate: Hashable {
        case person(UUID)
        case inbox(InboxState)
        /// A search for this exact term.
        case search(String)
    }

    private struct State {
        var gated: Set<Gate> = []
        var waiters: [Gate: [CheckedContinuation<Void, Never>]] = [:]
        var holdsTasks = false
        var taskWaiters: [CheckedContinuation<Void, Never>] = []
        var cancelledSearches: [String] = []
    }

    let inner: FakeDocumentServer
    private let state = Mutex(State())

    init(_ inner: FakeDocumentServer) {
        self.inner = inner
    }

    /// The list for `personID` waits from now on until `open(_:)`.
    func close(_ personID: UUID) {
        close(gate: .person(personID))
    }

    func isWaiting(_ personID: UUID) -> Bool {
        isWaiting(gate: .person(personID))
    }

    func open(_ personID: UUID) {
        open(gate: .person(personID))
    }

    func close(gate: Gate) {
        state.withLock { _ = $0.gated.insert(gate) }
    }

    func isWaiting(gate: Gate) -> Bool {
        state.withLock { !($0.waiters[gate] ?? []).isEmpty }
    }

    /// How many lists wait at `gate`.
    func waitingCount(gate: Gate) -> Int {
        state.withLock { $0.waiters[gate]?.count ?? 0 }
    }

    /// Lets only the list that came last through `gate`; the gate stays closed for the others.
    func releaseNewest(gate: Gate) {
        let waiter = state.withLock { $0.waiters[gate]?.popLast() }
        waiter?.resume()
    }

    func open(gate: Gate) {
        let waiters = state.withLock { state in
            state.gated.remove(gate)
            return state.waiters.removeValue(forKey: gate) ?? []
        }
        for waiter in waiters { waiter.resume() }
    }

    /// Completing and reopening a task waits from now on until `releaseTasks()`.
    func holdTasks() {
        state.withLock { $0.holdsTasks = true }
    }

    var heldTaskCalls: Int {
        state.withLock { $0.taskWaiters.count }
    }

    func releaseTasks() {
        let waiters = state.withLock { state in
            state.holdsTasks = false
            defer { state.taskWaiters = [] }
            return state.taskWaiters
        }
        for waiter in waiters { waiter.resume() }
    }

    private func waitIfTasksHeld() async {
        await withCheckedContinuation { continuation in
            let waits = state.withLock { state in
                guard state.holdsTasks else { return false }
                state.taskWaiters.append(continuation)
                return true
            }
            if !waits { continuation.resume() }
        }
    }

    private func wait(at gate: Gate) async {
        await withCheckedContinuation { continuation in
            let waits = state.withLock { state in
                guard state.gated.contains(gate) else { return false }
                state.waiters[gate, default: []].append(continuation)
                return true
            }
            if !waits { continuation.resume() }
        }
    }

    func documents(in scope: DocumentScope, filter: DocumentFilter) async throws -> [DocumentSummary] {
        let gate: Gate? = filter.personID.map(Gate.person) ?? filter.inboxState.map(Gate.inbox)
        if let gate { await wait(at: gate) }
        return try await inner.documents(in: scope, filter: filter)
    }

    /// A held search that was cancelled meanwhile ends as URLSession ends a cancelled request.
    func search(_ query: DocumentSearchQuery, in scope: DocumentScope) async throws -> DocumentSearchPage {
        await wait(at: .search(query.text))
        if Task.isCancelled {
            state.withLock { $0.cancelledSearches.append(query.text) }
            throw CancellationError()
        }
        return try await inner.search(query, in: scope)
    }

    func searchWasCancelled(_ text: String) -> Bool {
        state.withLock { $0.cancelledSearches.contains(text) }
    }

    func inboxCounts(in scope: DocumentScope) async throws -> InboxCounts {
        try await inner.inboxCounts(in: scope)
    }

    func document(_ id: UUID, in scope: DocumentScope) async throws -> DocumentDetail {
        try await inner.document(id, in: scope)
    }

    func pageImage(document id: UUID, index: Int, in scope: DocumentScope) async throws -> Data {
        try await inner.pageImage(document: id, index: index, in: scope)
    }

    func confirm(_ id: UUID, review: ConfirmedReview, in scope: DocumentScope) async throws -> DocumentDetail {
        try await inner.confirm(id, review: review, in: scope)
    }

    func retryProcessing(_ id: UUID, in scope: DocumentScope) async throws -> DocumentDetail {
        try await inner.retryProcessing(id, in: scope)
    }

    func persons(in scope: DocumentScope) async throws -> [Person] {
        try await inner.persons(in: scope)
    }

    func createPerson(named name: String, in scope: DocumentScope) async throws -> Person {
        try await inner.createPerson(named: name, in: scope)
    }

    func labels(in scope: DocumentScope) async throws -> [DocumentLabel] {
        try await inner.labels(in: scope)
    }

    func setAddressees(_ ids: [UUID], document: UUID, in scope: DocumentScope) async throws -> DocumentDetail {
        try await inner.setAddressees(ids, document: document, in: scope)
    }

    func setLabels(_ ids: [UUID], document: UUID, in scope: DocumentScope) async throws -> DocumentDetail {
        try await inner.setLabels(ids, document: document, in: scope)
    }

    func acceptSuggestion(_ id: UUID, document: UUID, in scope: DocumentScope) async throws -> DocumentDetail {
        try await inner.acceptSuggestion(id, document: document, in: scope)
    }

    func dismissSuggestion(_ id: UUID, document: UUID, in scope: DocumentScope) async throws -> DocumentDetail {
        try await inner.dismissSuggestion(id, document: document, in: scope)
    }

    func openTasks(in scope: DocumentScope) async throws -> [WorkspaceTask] {
        try await inner.openTasks(in: scope)
    }

    func completeTask(_ id: UUID, in scope: DocumentScope) async throws -> WorkspaceTask {
        await waitIfTasksHeld()
        return try await inner.completeTask(id, in: scope)
    }

    func reopenTask(_ id: UUID, in scope: DocumentScope) async throws -> WorkspaceTask {
        await waitIfTasksHeld()
        return try await inner.reopenTask(id, in: scope)
    }
}
