import Foundation
import Synchronization

/// A `DocumentServer` whose answers are set per test or preview and which records every call.
/// Lives in the library (not in a test target) because several test targets and previews use it.
public final class FakeDocumentServer: DocumentServer {
    public enum Call: Equatable, Sendable {
        case list(URL, DocumentFilter)
        case inboxCounts(URL)
        case detail(URL, UUID)
        case page(URL, UUID, Int)
        case confirm(URL, UUID, ConfirmedReview)
        case retry(URL, UUID)
        case persons(URL)
        case createPerson(URL, String)
        case labels(URL)
        case setAddressees(URL, UUID, [UUID])
        case setLabels(URL, UUID, [UUID])
        case acceptSuggestion(URL, UUID, UUID)
        case dismissSuggestion(URL, UUID, UUID)
        case openTasks(URL)
        case completeTask(URL, UUID)
        case reopenTask(URL, UUID)
    }

    private struct State {
        var calls: [Call] = []
        var tokens: [String] = []
        var list: @Sendable (URL, DocumentFilter) throws -> [DocumentSummary] = { _, _ in [] }
        /// `nil` counts what the unfiltered list holds, as a server would.
        var inboxCounts: (@Sendable (URL) throws -> InboxCounts)?
        var detail: @Sendable (URL, UUID) throws -> DocumentDetail
        var page: @Sendable (URL, UUID, Int) throws -> Data = { _, _, _ in Data([0xFF, 0xD8, 0xFF]) }
        var confirm: (@Sendable (URL, UUID, ConfirmedReview) throws -> DocumentDetail)?
        var retry: (@Sendable (URL, UUID) throws -> DocumentDetail)?
        var persons: @Sendable (URL) throws -> [Person] = { _ in DocumentFixtures.persons }
        var createPerson: @Sendable (URL, String) throws -> Person = { _, name in
            Person(id: UUID(), displayName: name, nameVariants: [], isArchived: false)
        }
        var labels: @Sendable (URL) throws -> [DocumentLabel] = { _ in DocumentFixtures.labels }
        /// Answers every call that changes a document's organisation (addressees, labels, suggestions);
        /// `nil` answers with `detail`.
        var organise: (@Sendable (URL, UUID) throws -> DocumentDetail)?
        var openTasks: @Sendable (URL) throws -> [WorkspaceTask] = { _ in [] }
        var completeTask: @Sendable (URL, UUID) throws -> WorkspaceTask = { _, id in
            FakeDocumentServer.task(id, done: true)
        }
        var reopenTask: @Sendable (URL, UUID) throws -> WorkspaceTask = { _, id in
            FakeDocumentServer.task(id, done: false)
        }
    }

    private let state: Mutex<State>

    public init(detail: @escaping @Sendable (URL, UUID) throws -> DocumentDetail) {
        state = Mutex(State(detail: detail))
    }

    public var calls: [Call] { state.withLock { $0.calls } }
    public var tokens: [String] { state.withLock { $0.tokens } }

    public func onList(_ answer: @escaping @Sendable (URL) throws -> [DocumentSummary]) {
        state.withLock { $0.list = { url, _ in try answer(url) } }
    }

    public func onList(_ answer: @escaping @Sendable (URL, DocumentFilter) throws -> [DocumentSummary]) {
        state.withLock { $0.list = answer }
    }

    public func onInboxCounts(_ answer: @escaping @Sendable (URL) throws -> InboxCounts) {
        state.withLock { $0.inboxCounts = answer }
    }

    public func onDetail(_ answer: @escaping @Sendable (URL, UUID) throws -> DocumentDetail) {
        state.withLock { $0.detail = answer }
    }

    public func onPage(_ answer: @escaping @Sendable (URL, UUID, Int) throws -> Data) {
        state.withLock { $0.page = answer }
    }

    public func onConfirm(_ answer: @escaping @Sendable (URL, UUID, ConfirmedReview) throws -> DocumentDetail) {
        state.withLock { $0.confirm = answer }
    }

    public func onRetry(_ answer: @escaping @Sendable (URL, UUID) throws -> DocumentDetail) {
        state.withLock { $0.retry = answer }
    }

    public func onPersons(_ answer: @escaping @Sendable (URL) throws -> [Person]) {
        state.withLock { $0.persons = answer }
    }

    public func onCreatePerson(_ answer: @escaping @Sendable (URL, String) throws -> Person) {
        state.withLock { $0.createPerson = answer }
    }

    public func onLabels(_ answer: @escaping @Sendable (URL) throws -> [DocumentLabel]) {
        state.withLock { $0.labels = answer }
    }

    /// The answer to `setAddressees`, `setLabels`, `acceptSuggestion` and `dismissSuggestion`, by document.
    public func onOrganise(_ answer: @escaping @Sendable (URL, UUID) throws -> DocumentDetail) {
        state.withLock { $0.organise = answer }
    }

    public func onOpenTasks(_ answer: @escaping @Sendable (URL) throws -> [WorkspaceTask]) {
        state.withLock { $0.openTasks = answer }
    }

    public func onCompleteTask(_ answer: @escaping @Sendable (URL, UUID) throws -> WorkspaceTask) {
        state.withLock { $0.completeTask = answer }
    }

    public func onReopenTask(_ answer: @escaping @Sendable (URL, UUID) throws -> WorkspaceTask) {
        state.withLock { $0.reopenTask = answer }
    }

    public func documents(in scope: DocumentScope, filter: DocumentFilter) async throws -> [DocumentSummary] {
        try record(.list(scope.url, filter), scope) { $0.list }(scope.url, filter)
    }

    public func inboxCounts(in scope: DocumentScope) async throws -> InboxCounts {
        let (counts, list) = record(.inboxCounts(scope.url), scope) { ($0.inboxCounts, $0.list) }
        if let counts { return try counts(scope.url) }
        let states = try list(scope.url, .all).map(\.inboxState)
        return InboxCounts(
            new: states.count { $0 == .new }, review: states.count { $0 == .review },
            unassigned: states.count { $0 == .unassigned }
        )
    }

    public func document(_ id: UUID, in scope: DocumentScope) async throws -> DocumentDetail {
        try record(.detail(scope.url, id), scope) { $0.detail }(scope.url, id)
    }

    public func pageImage(document id: UUID, index: Int, in scope: DocumentScope) async throws -> Data {
        try record(.page(scope.url, id, index), scope) { $0.page }(scope.url, id, index)
    }

    public func confirm(
        _ id: UUID, review: ConfirmedReview, in scope: DocumentScope
    ) async throws -> DocumentDetail {
        let (confirm, detail) = record(.confirm(scope.url, id, review), scope) { ($0.confirm, $0.detail) }
        return try confirm?(scope.url, id, review) ?? detail(scope.url, id)
    }

    public func retryProcessing(_ id: UUID, in scope: DocumentScope) async throws -> DocumentDetail {
        let (retry, detail) = record(.retry(scope.url, id), scope) { ($0.retry, $0.detail) }
        return try retry?(scope.url, id) ?? detail(scope.url, id)
    }

    public func persons(in scope: DocumentScope) async throws -> [Person] {
        try record(.persons(scope.url), scope) { $0.persons }(scope.url)
    }

    public func createPerson(named name: String, in scope: DocumentScope) async throws -> Person {
        try record(.createPerson(scope.url, name), scope) { $0.createPerson }(scope.url, name)
    }

    public func labels(in scope: DocumentScope) async throws -> [DocumentLabel] {
        try record(.labels(scope.url), scope) { $0.labels }(scope.url)
    }

    public func setAddressees(
        _ ids: [UUID], document: UUID, in scope: DocumentScope
    ) async throws -> DocumentDetail {
        try organise(.setAddressees(scope.url, document, ids), document: document, scope)
    }

    public func setLabels(_ ids: [UUID], document: UUID, in scope: DocumentScope) async throws -> DocumentDetail {
        try organise(.setLabels(scope.url, document, ids), document: document, scope)
    }

    public func acceptSuggestion(
        _ id: UUID, document: UUID, in scope: DocumentScope
    ) async throws -> DocumentDetail {
        try organise(.acceptSuggestion(scope.url, document, id), document: document, scope)
    }

    public func dismissSuggestion(
        _ id: UUID, document: UUID, in scope: DocumentScope
    ) async throws -> DocumentDetail {
        try organise(.dismissSuggestion(scope.url, document, id), document: document, scope)
    }

    public func openTasks(in scope: DocumentScope) async throws -> [WorkspaceTask] {
        try record(.openTasks(scope.url), scope) { $0.openTasks }(scope.url)
    }

    public func completeTask(_ id: UUID, in scope: DocumentScope) async throws -> WorkspaceTask {
        try record(.completeTask(scope.url, id), scope) { $0.completeTask }(scope.url, id)
    }

    public func reopenTask(_ id: UUID, in scope: DocumentScope) async throws -> WorkspaceTask {
        try record(.reopenTask(scope.url, id), scope) { $0.reopenTask }(scope.url, id)
    }

    /// The default answer to completing or reopening a task.
    fileprivate static func task(_ id: UUID, done: Bool) -> WorkspaceTask {
        WorkspaceTask(id: id, type: "", description: "", deadline: nil, isDone: done, documentID: nil, sender: "")
    }

    private func organise(_ call: Call, document: UUID, _ scope: DocumentScope) throws -> DocumentDetail {
        let (organise, detail) = record(call, scope) { ($0.organise, $0.detail) }
        return try organise?(scope.url, document) ?? detail(scope.url, document)
    }

    private func record<Answer>(
        _ call: Call, _ scope: DocumentScope, _ answer: (State) -> Answer
    ) -> Answer {
        state.withLock { state in
            state.calls.append(call)
            state.tokens.append(scope.token)
            return answer(state)
        }
    }
}
