import Foundation

/// "Mijn taken" (host PR #36).
extension FakeDocumentServer {
    public func onMyTasks(_ answer: @escaping @Sendable (URL, MyTasksPart, MyTasksStatus) throws -> MyTasks) {
        state.withLock { $0.myTasks = answer }
    }

    public func onMyTaskCounts(_ answer: @escaping @Sendable (URL) throws -> MyTaskCounts) {
        state.withLock { $0.myTaskCounts = answer }
    }

    public func onAssignTask(_ answer: @escaping @Sendable (URL, UUID, UUID?) throws -> WorkspaceTask) {
        state.withLock { $0.assignTask = answer }
    }

    public func onTaskAssignees(_ answer: @escaping @Sendable (URL, UUID) throws -> [TaskAssignee]) {
        state.withLock { $0.taskAssignees = answer }
    }

    public func onSetTaskDeadline(_ answer: @escaping @Sendable (URL, UUID, CalendarDate?) throws -> WorkspaceTask) {
        state.withLock { $0.setTaskDeadline = answer }
    }

    public func onCurrentUserID(_ answer: @escaping @Sendable (URL) throws -> UUID) {
        state.withLock { $0.currentUserID = answer }
    }

    public func myTasks(part: MyTasksPart, status: MyTasksStatus, in scope: DocumentScope) async throws -> MyTasks {
        try record(.myTasks(scope.url, part, status), scope) { $0.myTasks }(scope.url, part, status)
    }

    public func myTaskCounts(in scope: DocumentScope) async throws -> MyTaskCounts {
        try record(.myTaskCounts(scope.url), scope) { $0.myTaskCounts }(scope.url)
    }

    public func assignTask(_ id: UUID, to user: UUID?, in scope: DocumentScope) async throws -> WorkspaceTask {
        try record(.assignTask(scope.url, id, user), scope) { $0.assignTask }(scope.url, id, user)
    }

    public func taskAssignees(_ id: UUID, in scope: DocumentScope) async throws -> [TaskAssignee] {
        try record(.taskAssignees(scope.url, id), scope) { $0.taskAssignees }(scope.url, id)
    }

    public func setTaskDeadline(
        _ id: UUID, to deadline: CalendarDate?, in scope: DocumentScope
    ) async throws -> WorkspaceTask {
        try record(.setTaskDeadline(scope.url, id, deadline), scope) { $0.setTaskDeadline }(scope.url, id, deadline)
    }

    public func currentUserID(in scope: DocumentScope) async throws -> UUID {
        try record(.currentUserID(scope.url), scope) { $0.currentUserID }(scope.url)
    }
}
