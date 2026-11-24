import Foundation

/// Why a document call did not give a result, in the terms a screen needs.
public enum DocumentsError: Error, Equatable, Sendable {
    /// The server no longer knows this device: back to pairing.
    case revoked
    /// The stored pairing is gone.
    case missingPairing
    case unreachable
    /// A server answered, but not with the pinned certificate.
    case notVerified
    /// The document or page does not exist (any more).
    case notFound
    /// The document changed meanwhile (confirmed elsewhere, no longer failed): load it again.
    case conflict
    /// The server refused what was sent.
    case invalid
    /// A person with this name exists already.
    case nameTaken
    /// The document is still being processed: try again in a moment.
    case busy
    /// The server does not know this request: it is older than the app (a 1b server has no task list).
    case notSupported
    /// HTTP 429: too many requests in a short time (searches: 30 a minute). Wait a moment.
    case tooManyRequests
    /// The letter is in the trash: it cannot be read until it is restored.
    case inTrash
    /// The member's role may not do this (a viewer).
    case forbidden
    /// Someone already chose for this duplicate pair (merged or dismissed elsewhere).
    case alreadyDecided
    /// The two letters of a pair are not visible to the same people: they cannot be merged.
    case visibilityDiffers
    /// The chosen person may not read the task's letter (or is a viewer): choose someone else.
    case assigneeCannotRead
    /// A task without a letter cannot be given to anyone.
    case taskWithoutLetter
    /// Someone else does the task already; only they or an admin can hand it on.
    case taskTaken
    case cancelled
    case failed
}

/// The documents of one workspace on the paired server: tries the pairing's addresses in order and sorts
/// every failure into a `DocumentsError`. Screens use this, not the server seam directly.
public struct WorkspaceDocuments: Sendable {
    public let workspaceID: UUID
    private let connection: ServerConnection
    private let store: ConnectionStore
    private let server: any DocumentServer
    private let onRevoked: @Sendable (UUID) async -> Void

    /// - Parameter onRevoked: called with this pairing's device before a call throws `.revoked`, whatever the
    ///   screen does with the error (also a call whose failure the screen ignores, such as the persons list or the
    ///   open tasks of a calendar sync). The app passes `AppModel.sessionRevoked(deviceID:)`: the one place where a
    ///   401 `not_authenticated` ends the session.
    public init(
        workspaceID: UUID, connection: ServerConnection, store: ConnectionStore, server: any DocumentServer,
        onRevoked: @escaping @Sendable (UUID) async -> Void = { _ in }
    ) {
        self.workspaceID = workspaceID
        self.connection = connection
        self.store = store
        self.server = server
        self.onRevoked = onRevoked
    }

    /// The device this pairing belongs to, for `AppModel.sessionRevoked(deviceID:)`.
    public var deviceID: UUID { connection.deviceID }

    /// The signed-in user's name, as the pairing stored it ("Jij doet dit" when they assigned a task to themselves).
    public var userName: String { connection.userName }

    public func list(filter: DocumentFilter = .all) async throws(DocumentsError) -> [DocumentSummary] {
        try await perform { try await server.documents(in: $0, filter: filter) }
    }

    /// One page of a search; `.tooManyRequests` after too many searches in a minute (429).
    public func search(_ query: DocumentSearchQuery) async throws(DocumentsError) -> DocumentSearchPage {
        try await perform { try await server.search(query, in: $0) }
    }

    public func inboxCounts() async throws(DocumentsError) -> InboxCounts {
        try await perform { try await server.inboxCounts(in: $0) }
    }

    public func detail(_ id: UUID) async throws(DocumentsError) -> DocumentDetail {
        try await perform { try await server.document(id, in: $0) }
    }

    public func pageImage(_ id: UUID, index: Int) async throws(DocumentsError) -> Data {
        try await perform { try await server.pageImage(document: id, index: index, in: $0) }
    }

    public func confirm(_ id: UUID, review: ConfirmedReview) async throws(DocumentsError) -> DocumentDetail {
        try await perform { try await server.confirm(id, review: review, in: $0) }
    }

    public func retryProcessing(_ id: UUID) async throws(DocumentsError) -> DocumentDetail {
        try await perform { try await server.retryProcessing(id, in: $0) }
    }

    public func persons() async throws(DocumentsError) -> [Person] {
        try await perform { try await server.persons(in: $0) }
    }

    public func createPerson(named name: String) async throws(DocumentsError) -> Person {
        try await perform { try await server.createPerson(named: name, in: $0) }
    }

    public func labels() async throws(DocumentsError) -> [DocumentLabel] {
        try await perform { try await server.labels(in: $0) }
    }

    public func setAddressees(_ ids: [UUID], document: UUID) async throws(DocumentsError) -> DocumentDetail {
        try await perform { try await server.setAddressees(ids, document: document, in: $0) }
    }

    public func setLabels(_ ids: [UUID], document: UUID) async throws(DocumentsError) -> DocumentDetail {
        try await perform { try await server.setLabels(ids, document: document, in: $0) }
    }

    public func acceptSuggestion(_ id: UUID, document: UUID) async throws(DocumentsError) -> DocumentDetail {
        try await perform { try await server.acceptSuggestion(id, document: document, in: $0) }
    }

    public func dismissSuggestion(_ id: UUID, document: UUID) async throws(DocumentsError) -> DocumentDetail {
        try await perform { try await server.dismissSuggestion(id, document: document, in: $0) }
    }

    public func openTasks() async throws(DocumentsError) -> [WorkspaceTask] {
        try await perform { try await server.openTasks(in: $0) }
    }

    public func completeTask(_ id: UUID) async throws(DocumentsError) -> WorkspaceTask {
        try await perform { try await server.completeTask(id, in: $0) }
    }

    public func reopenTask(_ id: UUID) async throws(DocumentsError) -> WorkspaceTask {
        try await perform { try await server.reopenTask(id, in: $0) }
    }

    public func trash(_ id: UUID) async throws(DocumentsError) -> TrashedDocument {
        try await perform { try await server.trash(id, in: $0) }
    }

    public func restore(_ id: UUID) async throws(DocumentsError) -> DocumentDetail {
        try await perform { try await server.restore(id, in: $0) }
    }

    public func trashList() async throws(DocumentsError) -> TrashList {
        try await perform { try await server.trashList(in: $0) }
    }

    public func duplicates() async throws(DocumentsError) -> [DuplicatePair] {
        try await perform { try await server.duplicates(in: $0) }
    }

    public func duplicate(_ id: UUID) async throws(DocumentsError) -> DuplicatePair {
        try await perform { try await server.duplicate(id, in: $0) }
    }

    public func mergeDuplicate(
        _ id: UUID, keep: UUID, completeTwinTasks: Bool
    ) async throws(DocumentsError) -> DocumentDetail {
        try await perform {
            try await server.mergeDuplicate(id, keep: keep, completeTwinTasks: completeTwinTasks, in: $0)
        }
    }

    public func dismissDuplicate(_ id: UUID) async throws(DocumentsError) {
        try await perform { try await server.dismissDuplicate(id, in: $0) }
    }

    public func myTasks(part: MyTasksPart, status: MyTasksStatus) async throws(DocumentsError) -> MyTasks {
        try await perform { try await server.myTasks(part: part, status: status, in: $0) }
    }

    public func myTaskCounts() async throws(DocumentsError) -> MyTaskCounts {
        try await perform { try await server.myTaskCounts(in: $0) }
    }

    public func assignTask(_ id: UUID, to user: UUID?) async throws(DocumentsError) -> WorkspaceTask {
        try await perform { try await server.assignTask(id, to: user, in: $0) }
    }

    public func taskAssignees(_ id: UUID) async throws(DocumentsError) -> [TaskAssignee] {
        try await perform { try await server.taskAssignees(id, in: $0) }
    }

    public func setTaskDeadline(_ id: UUID, to deadline: CalendarDate?) async throws(DocumentsError) -> WorkspaceTask {
        try await perform { try await server.setTaskDeadline(id, to: deadline, in: $0) }
    }

    public func currentUserID() async throws(DocumentsError) -> UUID {
        try await perform { try await server.currentUserID(in: $0) }
    }

    public func menuCounts() async throws(DocumentsError) -> MenuCounts {
        try await perform { try await server.menuCounts(in: $0) }
    }

    public func markRead(_ id: UUID) async throws(DocumentsError) {
        try await perform { try await server.markRead(id, in: $0) }
    }

    public func markUnread(_ id: UUID) async throws(DocumentsError) {
        try await perform { try await server.markUnread(id, in: $0) }
    }

    /// At most `markReadLimit` ids per call (the server's cap); more are sent in several calls.
    public func markRead(_ ids: [UUID]) async throws(DocumentsError) -> Int {
        var marked = 0
        var rest = ids[...]
        while !rest.isEmpty {
            let part = Array(rest.prefix(Self.markReadLimit))
            rest = rest.dropFirst(part.count)
            marked += try await perform { try await server.markRead(part, in: $0) }
        }
        return marked
    }

    public func lingeringLetters() async throws(DocumentsError) -> LingeringLetters {
        try await perform { try await server.lingeringLetters(in: $0) }
    }

    /// The most letters `markDocumentsRead` takes in one call.
    public static let markReadLimit = 200

    /// The tasks the phone's reminders and calendar follow: the member's own ("Mijn taken", the default) or every
    /// task they may see. Never "Op te pakken" (asked as the own tasks). A server before "Mijn taken" (404) gives
    /// every open task of the workspace, as before; any other failure is a failure, never that fallback.
    public func phoneTasks(_ part: MyTasksPart) async throws(DocumentsError) -> [WorkspaceTask] {
        do {
            return try await myTasks(part: part == .all ? .all : .mine, status: .open).items
        } catch .notSupported {
            return try await openTasks()
        }
    }

    private func perform<Result: Sendable>(
        _ call: (DocumentScope) async throws -> Result
    ) async throws(DocumentsError) -> Result {
        let token = try storedToken()
        let trust = ServerTrust(caCertificateDER: connection.caCertificateDER)
        var sawUntrusted = false
        var sawForeign401 = false
        for url in connection.urls {
            let scope = DocumentScope(url: url, trust: trust, token: token, workspaceID: workspaceID)
            do {
                return try await call(scope)
            } catch ServerError.unreachable {
                continue
            } catch ServerError.untrusted {
                sawUntrusted = true
            } catch ServerError.other("http_401") {
                // Not the host's verdict (no `not_authenticated`): try the next address, never a revocation.
                sawForeign401 = true
            } catch ServerError.unauthorized {
                await onRevoked(connection.deviceID)
                throw .revoked
            } catch is CancellationError {
                throw .cancelled
            } catch let ServerError.other(code) {
                throw Self.verdict(code)
            } catch {
                throw Self.otherFailure(error)
            }
        }
        if Task.isCancelled { throw .cancelled }
        if sawUntrusted { throw .notVerified }
        throw sawForeign401 ? .failed : .unreachable
    }

    private func storedToken() throws(DocumentsError) -> String {
        let stored: (connection: ServerConnection, token: String)?
        do {
            stored = try store.load()
        } catch {
            throw .failed
        }
        guard let stored else { throw .missingPairing }
        return stored.token
    }

    /// A 429 asks to wait; anything else this seam does not sort is a plain failure.
    private static func otherFailure(_ error: any Error) -> DocumentsError {
        (error as? ServerError) == .tooManyAttempts ? .tooManyRequests : .failed
    }

    private static func verdict(_ code: String) -> DocumentsError {
        // Our own codes all pass through; a 404 without one is the server's catch-all for a path it lacks.
        verdicts[code] ?? .failed
    }

    private static let verdicts: [String: DocumentsError] = [
        "document_not_found": .notFound, "page_not_found": .notFound, "workspace_not_found": .notFound,
        "person_not_found": .notFound, "label_not_found": .notFound, "suggestion_not_found": .notFound,
        "task_not_found": .notFound, "duplicate_not_found": .notFound,
        "document_not_reviewable": .conflict, "document_not_failed": .conflict,
        "validation_error": .invalid,
        "person_exists": .nameTaken,
        "document_processing": .busy,
        "document_in_trash": .inTrash,
        "forbidden": .forbidden,
        "duplicate_not_open": .alreadyDecided,
        "duplicate_visibility_differs": .visibilityDiffers,
        "assignee_cannot_read": .assigneeCannotRead,
        "task_without_letter": .taskWithoutLetter,
        "task_taken": .taskTaken,
        "http_404": .notSupported
    ]

}
