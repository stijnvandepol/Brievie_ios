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

    public init(workspaceID: UUID, connection: ServerConnection, store: ConnectionStore, server: any DocumentServer) {
        self.workspaceID = workspaceID
        self.connection = connection
        self.store = store
        self.server = server
    }

    /// The device this pairing belongs to, for `AppModel.sessionRevoked(deviceID:)`.
    public var deviceID: UUID { connection.deviceID }

    public func list() async throws(DocumentsError) -> [DocumentSummary] {
        try await perform { try await server.documents(in: $0) }
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

    private func perform<Result: Sendable>(
        _ call: (DocumentScope) async throws -> Result
    ) async throws(DocumentsError) -> Result {
        let token = try storedToken()
        let trust = ServerTrust(caCertificateDER: connection.caCertificateDER)
        var sawUntrusted = false
        for url in connection.urls {
            let scope = DocumentScope(url: url, trust: trust, token: token, workspaceID: workspaceID)
            do {
                return try await call(scope)
            } catch ServerError.unreachable {
                continue
            } catch ServerError.untrusted {
                sawUntrusted = true
            } catch ServerError.unauthorized {
                throw .revoked
            } catch is CancellationError {
                throw .cancelled
            } catch let ServerError.other(code) {
                throw Self.verdict(code)
            } catch {
                throw .failed
            }
        }
        if Task.isCancelled { throw .cancelled }
        throw sawUntrusted ? .notVerified : .unreachable
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

    private static func verdict(_ code: String) -> DocumentsError {
        switch code {
        case "document_not_found", "page_not_found", "workspace_not_found": .notFound
        case "document_not_reviewable", "document_not_failed": .conflict
        case "validation_error": .invalid
        default: .failed
        }
    }
}
