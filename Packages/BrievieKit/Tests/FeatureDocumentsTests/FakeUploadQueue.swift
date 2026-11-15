import BrievieCore
import BrievieScan
import Foundation
import Synchronization

final class FakeUploadQueue: UploadQueue {
    private struct State {
        var items: [UploadItem] = []
        var enqueued: [[ScannedPage]] = []
        var retried: [UUID] = []
        var deleted: [UUID] = []
        var enqueueError: UploadQueueError?
        var continuations: [AsyncStream<[UUID: Double]>.Continuation] = []
    }

    private let state = Mutex(State())

    var enqueued: [[ScannedPage]] { state.withLock { $0.enqueued } }
    var retried: [UUID] { state.withLock { $0.retried } }
    var deleted: [UUID] { state.withLock { $0.deleted } }

    var progressSubscriberCount: Int {
        get async { state.withLock { $0.continuations.count } }
    }

    func set(_ items: [UploadItem]) {
        state.withLock { $0.items = items }
    }

    func failEnqueue(with error: UploadQueueError) {
        state.withLock { $0.enqueueError = error }
    }

    func sendProgress(_ progress: [UUID: Double]) {
        for continuation in state.withLock({ $0.continuations }) {
            continuation.yield(progress)
        }
    }

    func finishProgress() {
        for continuation in state.withLock({ $0.continuations }) {
            continuation.finish()
        }
    }

    static func item(
        id: UUID = UUID(), workspaceID: UUID, state: UploadItem.State = .waiting, failureCode: String? = nil,
        pageCount: Int = 1, createdAt: Date = Date(timeIntervalSince1970: 1_794_650_400)
    ) -> UploadItem {
        UploadItem(
            id: id, workspaceID: workspaceID, deviceID: UUID(), createdAt: createdAt, pageCount: pageCount,
            bodyByteCount: 10, boundary: "b", state: state, attempt: 0, urlIndex: 0, nextAttemptAt: nil,
            failureCode: failureCode
        )
    }

    func enqueue(pages: [ScannedPage], workspaceID: UUID) async throws(UploadQueueError) -> UploadItem {
        let error = state.withLock { state -> UploadQueueError? in
            state.enqueued.append(pages)
            return state.enqueueError
        }
        if let error { throw error }
        let item = Self.item(workspaceID: workspaceID, pageCount: pages.count)
        state.withLock { $0.items.append(item) }
        return item
    }

    func items() async -> [UploadItem] {
        state.withLock { $0.items }
    }

    func retry(_ id: UUID) async {
        state.withLock { $0.retried.append(id) }
    }

    func delete(_ id: UUID) async {
        state.withLock {
            $0.deleted.append(id)
            $0.items.removeAll { $0.id == id }
        }
    }

    func removeAll() async throws {
        state.withLock { $0.items.removeAll() }
    }

    func progressUpdates() async -> AsyncStream<[UUID: Double]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [UUID: Double].self)
        state.withLock { $0.continuations.append(continuation) }
        return stream
    }
}
