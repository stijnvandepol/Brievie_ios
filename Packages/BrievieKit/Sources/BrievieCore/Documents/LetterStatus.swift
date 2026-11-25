import Foundation

/// Where a letter stands (host PR #50), as the server decides it. Raw values match the API.
public enum LetterStatus: String, Equatable, Sendable {
    /// Not checked yet.
    case new
    /// Checked, with a task still open.
    case open
    /// Every open task waits for a reply.
    case waiting
    /// Checked, nothing open.
    case handled
    /// The server did not say (one before host PR #50): the app shows no status.
    case none = ""
    case unknown

    public init(api: String?) {
        self = Self(rawValue: api ?? "") ?? .unknown
    }
}

/// Defaults for servers that predate letter status (host PR #50), and for the test servers.
public extension DocumentServer {
    /// For servers that predate letter status: the plain list (they have no waiting or snoozed tasks).
    func myTasks(
        part: MyTasksPart, status: MyTasksStatus, includeWaiting: Bool, in scope: DocumentScope
    ) async throws -> MyTasks {
        try await myTasks(part: part, status: status, in: scope)
    }

    func handleDocument(
        _ id: UUID, taskIDs: [UUID], paymentsConfirmed: Bool, in scope: DocumentScope
    ) async throws -> DocumentDetail {
        throw ServerError.other("http_404")
    }

    func setTaskWaiting(_ id: UUID, until: CalendarDate?, in scope: DocumentScope) async throws -> WorkspaceTask {
        throw ServerError.other("http_404")
    }

    func snoozeTask(_ id: UUID, until: CalendarDate?, in scope: DocumentScope) async throws -> WorkspaceTask {
        throw ServerError.other("http_404")
    }
}
