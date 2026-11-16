import BrievieCore
import Foundation
import Synchronization

/// A `FakeDocumentServer` whose list for a chosen person waits until the test opens its gate, to play out a
/// slow answer for a scope the user has already left.
final class GatedDocumentServer: DocumentServer {
    private struct State {
        var gated: Set<UUID> = []
        var waiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
    }

    let inner: FakeDocumentServer
    private let state = Mutex(State())

    init(_ inner: FakeDocumentServer) {
        self.inner = inner
    }

    /// The list for `personID` waits from now on until `open(_:)`.
    func close(_ personID: UUID) {
        state.withLock { _ = $0.gated.insert(personID) }
    }

    func isWaiting(_ personID: UUID) -> Bool {
        state.withLock { !($0.waiters[personID] ?? []).isEmpty }
    }

    func open(_ personID: UUID) {
        let waiters = state.withLock { state in
            state.gated.remove(personID)
            return state.waiters.removeValue(forKey: personID) ?? []
        }
        for waiter in waiters { waiter.resume() }
    }

    func documents(in scope: DocumentScope, filter: DocumentFilter) async throws -> [DocumentSummary] {
        if let personID = filter.personID {
            await withCheckedContinuation { continuation in
                let waits = state.withLock { state in
                    guard state.gated.contains(personID) else { return false }
                    state.waiters[personID, default: []].append(continuation)
                    return true
                }
                if !waits { continuation.resume() }
            }
        }
        return try await inner.documents(in: scope, filter: filter)
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
        try await inner.completeTask(id, in: scope)
    }

    func reopenTask(_ id: UUID, in scope: DocumentScope) async throws -> WorkspaceTask {
        try await inner.reopenTask(id, in: scope)
    }
}
