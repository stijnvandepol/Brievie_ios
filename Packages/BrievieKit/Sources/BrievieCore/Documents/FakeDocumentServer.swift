import Foundation
import Synchronization

/// A `DocumentServer` whose answers are set per test or preview and which records every call.
/// Lives in the library (not in a test target) because several test targets and previews use it.
public final class FakeDocumentServer: DocumentServer {
    public enum Call: Equatable, Sendable {
        case list(URL)
        case detail(URL, UUID)
        case page(URL, UUID, Int)
        case confirm(URL, UUID, ConfirmedReview)
        case retry(URL, UUID)
    }

    private struct State {
        var calls: [Call] = []
        var tokens: [String] = []
        var list: @Sendable (URL) throws -> [DocumentSummary] = { _ in [] }
        var detail: @Sendable (URL, UUID) throws -> DocumentDetail
        var page: @Sendable (URL, UUID, Int) throws -> Data = { _, _, _ in Data([0xFF, 0xD8, 0xFF]) }
        var confirm: (@Sendable (URL, UUID, ConfirmedReview) throws -> DocumentDetail)?
        var retry: (@Sendable (URL, UUID) throws -> DocumentDetail)?
    }

    private let state: Mutex<State>

    public init(detail: @escaping @Sendable (URL, UUID) throws -> DocumentDetail) {
        state = Mutex(State(detail: detail))
    }

    public var calls: [Call] { state.withLock { $0.calls } }
    public var tokens: [String] { state.withLock { $0.tokens } }

    public func onList(_ answer: @escaping @Sendable (URL) throws -> [DocumentSummary]) {
        state.withLock { $0.list = answer }
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

    public func documents(in scope: DocumentScope) async throws -> [DocumentSummary] {
        try record(.list(scope.url), scope) { $0.list }(scope.url)
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
