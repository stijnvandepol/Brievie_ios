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
        switch code {
        case "document_not_found", "page_not_found", "workspace_not_found", "person_not_found", "label_not_found",
             "suggestion_not_found", "task_not_found": .notFound
        case "document_not_reviewable", "document_not_failed": .conflict
        case "validation_error": .invalid
        case "person_exists": .nameTaken
        case "document_processing": .busy
        case "document_in_trash": .inTrash
        case "forbidden": .forbidden
        // Our own codes all pass through; a 404 without one is the server's catch-all for a path it lacks.
        case "http_404": .notSupported
        default: .failed
        }
    }
}
