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
        case search(URL, DocumentSearchQuery)
        case trash(URL, UUID)
        case restore(URL, UUID)
        case trashList(URL)
        case duplicates(URL)
        case duplicate(URL, UUID)
        case merge(URL, UUID, keep: UUID, completeTwinTasks: Bool)
        case dismissDuplicate(URL, UUID)
        case myTasks(URL, MyTasksPart, MyTasksStatus)
        case myTaskCounts(URL)
        case assignTask(URL, UUID, UUID?)
        case taskAssignees(URL, UUID)
        case setTaskDeadline(URL, UUID, CalendarDate?)
        case currentUserID(URL)
        case menuCounts(URL)
        case markRead(URL, UUID)
        case markUnread(URL, UUID)
        case markManyRead(URL, [UUID])
        case lingering(URL)
        case handleDocument(URL, UUID, [UUID], paymentsConfirmed: Bool)
        case setTaskWaiting(URL, UUID, CalendarDate?)
        case snoozeTask(URL, UUID, CalendarDate?)
    }

    /// The user `currentUserID` answers with unless a test sets another.
    public static let currentUser = UUID(uuidString: "0E3A54C1-7B2F-4D6E-9A8B-1C2D3E4F5A6B") ?? UUID()

    // Internal (not private) so the extensions in `FakeDocumentServer+Reading.swift` reach them.
    let state: Mutex<FakeServerState>

    public init(detail: @escaping @Sendable (URL, UUID) throws -> DocumentDetail) {
        state = Mutex(FakeServerState(detail: detail))
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

    public func onSearch(_ answer: @escaping @Sendable (URL, DocumentSearchQuery) throws -> DocumentSearchPage) {
        state.withLock { $0.search = answer }
    }

    public func onTrash(_ answer: @escaping @Sendable (URL, UUID) throws -> TrashedDocument) {
        state.withLock { $0.trash = answer }
    }

    public func onRestore(_ answer: @escaping @Sendable (URL, UUID) throws -> DocumentDetail) {
        state.withLock { $0.restore = answer }
    }

    public func onTrashList(_ answer: @escaping @Sendable (URL) throws -> TrashList) {
        state.withLock { $0.trashList = answer }
    }

    public func onDuplicates(_ answer: @escaping @Sendable (URL) throws -> [DuplicatePair]) {
        state.withLock { $0.duplicates = answer }
    }

    public func onDuplicate(_ answer: @escaping @Sendable (URL, UUID) throws -> DuplicatePair) {
        state.withLock { $0.duplicate = answer }
    }

    /// The answer to a merge: pair id, kept letter, the twin choice.
    public func onMerge(_ answer: @escaping @Sendable (URL, UUID, UUID, Bool) throws -> DocumentDetail) {
        state.withLock { $0.merge = answer }
    }

    public func onDismissDuplicate(_ answer: @escaping @Sendable (URL, UUID) throws -> Void) {
        state.withLock { $0.dismissDuplicate = answer }
    }

    public func duplicates(in scope: DocumentScope) async throws -> [DuplicatePair] {
        try record(.duplicates(scope.url), scope) { $0.duplicates }(scope.url)
    }

    public func duplicate(_ id: UUID, in scope: DocumentScope) async throws -> DuplicatePair {
        let (duplicate, list) = record(.duplicate(scope.url, id), scope) { ($0.duplicate, $0.duplicates) }
        if let duplicate { return try duplicate(scope.url, id) }
        guard let pair = try list(scope.url).first(where: { $0.id == id }) else {
            throw ServerError.other("duplicate_not_found")
        }
        return pair
    }

    public func mergeDuplicate(
        _ id: UUID, keep: UUID, completeTwinTasks: Bool, in scope: DocumentScope
    ) async throws -> DocumentDetail {
        let call = Call.merge(scope.url, id, keep: keep, completeTwinTasks: completeTwinTasks)
        let (merge, detail) = record(call, scope) { ($0.merge, $0.detail) }
        return try merge?(scope.url, id, keep, completeTwinTasks) ?? detail(scope.url, keep)
    }

    public func dismissDuplicate(_ id: UUID, in scope: DocumentScope) async throws {
        try record(.dismissDuplicate(scope.url, id), scope) { $0.dismissDuplicate }(scope.url, id)
    }

    public func trash(_ id: UUID, in scope: DocumentScope) async throws -> TrashedDocument {
        try record(.trash(scope.url, id), scope) { $0.trash }(scope.url, id)
    }

    public func restore(_ id: UUID, in scope: DocumentScope) async throws -> DocumentDetail {
        try record(.restore(scope.url, id), scope) { $0.restore }(scope.url, id)
    }

    public func trashList(in scope: DocumentScope) async throws -> TrashList {
        try record(.trashList(scope.url), scope) { $0.trashList }(scope.url)
    }

    public func search(_ query: DocumentSearchQuery, in scope: DocumentScope) async throws -> DocumentSearchPage {
        try record(.search(scope.url, query), scope) { $0.search }(scope.url, query)
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

    func record<Answer>(
        _ call: Call, _ scope: DocumentScope, _ answer: (FakeServerState) -> Answer
    ) -> Answer {
        state.withLock { state in
            state.calls.append(call)
            state.tokens.append(scope.token)
            return answer(state)
        }
    }
}

/// What `FakeDocumentServer` answers and has recorded.
struct FakeServerState {
    typealias Call = FakeDocumentServer.Call
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
    var search: @Sendable (URL, DocumentSearchQuery) throws -> DocumentSearchPage = { _, _ in
        DocumentSearchPage(hits: [])
    }
    var trash: @Sendable (URL, UUID) throws -> TrashedDocument = { _, id in DocumentFixtures.trashed(id: id) }
    var restore: @Sendable (URL, UUID) throws -> DocumentDetail = { _, id in DocumentFixtures.detail(id: id) }
    var trashList: @Sendable (URL) throws -> TrashList = { _ in TrashList(items: []) }
    var duplicates: @Sendable (URL) throws -> [DuplicatePair] = { _ in [] }
    /// `nil` answers with the pair of that id from `duplicates`, or `duplicate_not_found`.
    var duplicate: (@Sendable (URL, UUID) throws -> DuplicatePair)?
    /// `nil` answers with `detail` of the kept letter.
    var merge: (@Sendable (URL, UUID, UUID, Bool) throws -> DocumentDetail)?
    var dismissDuplicate: @Sendable (URL, UUID) throws -> Void = { _, _ in }
    var myTasks: @Sendable (URL, MyTasksPart, MyTasksStatus) throws -> MyTasks = { _, _, _ in
        MyTasks(items: [], today: CalendarDate(year: 2026, month: 11, day: 21))
    }
    var myTaskCounts: @Sendable (URL) throws -> MyTaskCounts = { _ in MyTaskCounts(mine: 0) }
    var assignTask: @Sendable (URL, UUID, UUID?) throws -> WorkspaceTask = { _, id, user in
        WorkspaceTask(
            id: id, type: "", description: "", deadline: nil, isDone: false, documentID: nil, sender: "",
            assignedToID: user
        )
    }
    var taskAssignees: @Sendable (URL, UUID) throws -> [TaskAssignee] = { _, _ in [] }
    var setTaskDeadline: @Sendable (URL, UUID, CalendarDate?) throws -> WorkspaceTask = { _, id, deadline in
        WorkspaceTask(
            id: id, type: "", description: "", deadline: deadline, isDone: false, documentID: nil, sender: ""
        )
    }
    var currentUserID: @Sendable (URL) throws -> UUID = { _ in FakeDocumentServer.currentUser }
    var menuCounts: @Sendable (URL) throws -> MenuCounts = { _ in MenuCounts() }
    var markRead: @Sendable (URL, UUID) throws -> Void = { _, _ in }
    var markUnread: @Sendable (URL, UUID) throws -> Void = { _, _ in }
    var markManyRead: @Sendable (URL, [UUID]) throws -> Int = { _, ids in ids.count }
    var lingering: @Sendable (URL) throws -> LingeringLetters = { _ in
        LingeringLetters(tooLongInInbox: [], notOpened: [], inboxDays: 2, unopenedDays: 5)
    }
    var handleDocument: @Sendable (URL, UUID, [UUID], Bool) throws -> DocumentDetail = { _, id, _, _ in
        DocumentFixtures.detail(id: id)
    }
    var taskChange: @Sendable (URL, UUID, CalendarDate?) throws -> WorkspaceTask = { _, id, _ in
        WorkspaceTask(id: id, type: "", description: "", deadline: nil, isDone: false, documentID: nil, sender: "")
    }
}
