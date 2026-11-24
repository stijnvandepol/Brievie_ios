import Foundation

/// "Mijn post", "Ongelezen" and "Blijft liggen" (host PR #44). By default the server knows them, with zero counts.
extension FakeDocumentServer {
    public func onMenuCounts(_ answer: @escaping @Sendable (URL) throws -> MenuCounts) {
        state.withLock { $0.menuCounts = answer }
    }

    public func onMarkRead(_ answer: @escaping @Sendable (URL, UUID) throws -> Void) {
        state.withLock { $0.markRead = answer }
    }

    public func onMarkUnread(_ answer: @escaping @Sendable (URL, UUID) throws -> Void) {
        state.withLock { $0.markUnread = answer }
    }

    public func onMarkManyRead(_ answer: @escaping @Sendable (URL, [UUID]) throws -> Int) {
        state.withLock { $0.markManyRead = answer }
    }

    public func onLingering(_ answer: @escaping @Sendable (URL) throws -> LingeringLetters) {
        state.withLock { $0.lingering = answer }
    }

    public func menuCounts(in scope: DocumentScope) async throws -> MenuCounts {
        try record(.menuCounts(scope.url), scope) { $0.menuCounts }(scope.url)
    }

    public func markRead(_ id: UUID, in scope: DocumentScope) async throws {
        try record(.markRead(scope.url, id), scope) { $0.markRead }(scope.url, id)
    }

    public func markUnread(_ id: UUID, in scope: DocumentScope) async throws {
        try record(.markUnread(scope.url, id), scope) { $0.markUnread }(scope.url, id)
    }

    public func markRead(_ ids: [UUID], in scope: DocumentScope) async throws -> Int {
        try record(.markManyRead(scope.url, ids), scope) { $0.markManyRead }(scope.url, ids)
    }

    public func lingeringLetters(in scope: DocumentScope) async throws -> LingeringLetters {
        try record(.lingering(scope.url), scope) { $0.lingering }(scope.url)
    }
}
