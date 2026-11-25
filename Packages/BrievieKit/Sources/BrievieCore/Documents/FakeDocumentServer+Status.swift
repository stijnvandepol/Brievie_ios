import Foundation

/// Letter status (host PR #50): "Brief afhandelen", "Wacht op reactie", "Uitstellen".
extension FakeDocumentServer {
    public func onHandleDocument(_ answer: @escaping @Sendable (URL, UUID, [UUID], Bool) throws -> DocumentDetail) {
        state.withLock { $0.handleDocument = answer }
    }

    /// One answer for both `setTaskWaiting` and `snoozeTask`; the recorded calls tell them apart.
    public func onTaskChange(_ answer: @escaping @Sendable (URL, UUID, CalendarDate?) throws -> WorkspaceTask) {
        state.withLock { $0.taskChange = answer }
    }

    public func myTasks(
        part: MyTasksPart, status: MyTasksStatus, includeWaiting: Bool, in scope: DocumentScope
    ) async throws -> MyTasks {
        try await myTasks(part: part, status: status, in: scope)
    }

    public func handleDocument(
        _ id: UUID, taskIDs: [UUID], paymentsConfirmed: Bool, in scope: DocumentScope
    ) async throws -> DocumentDetail {
        try record(.handleDocument(scope.url, id, taskIDs, paymentsConfirmed: paymentsConfirmed), scope) {
            $0.handleDocument
        }(scope.url, id, taskIDs, paymentsConfirmed)
    }

    public func setTaskWaiting(
        _ id: UUID, until: CalendarDate?, in scope: DocumentScope
    ) async throws -> WorkspaceTask {
        try record(.setTaskWaiting(scope.url, id, until), scope) { $0.taskChange }(scope.url, id, until)
    }

    public func snoozeTask(_ id: UUID, until: CalendarDate?, in scope: DocumentScope) async throws -> WorkspaceTask {
        try record(.snoozeTask(scope.url, id, until), scope) { $0.taskChange }(scope.url, id, until)
    }
}
