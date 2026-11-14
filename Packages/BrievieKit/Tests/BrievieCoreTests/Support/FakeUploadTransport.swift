@testable import BrievieCore
import Foundation
import Synchronization

/// Records what the coordinator asks for; the test feeds the events a real transport would report.
final class FakeUploadTransport: UploadTransport {
    struct Start: Equatable {
        let itemID: UUID
        let deviceID: UUID
        let url: URL
        let token: String
        let earliestBegin: Date?
    }

    private struct State {
        var starts: [Start] = []
        var running: Set<UUID> = []
        var cancelled: [UUID] = []
    }

    let events: AsyncStream<UploadEvent>
    private let continuation: AsyncStream<UploadEvent>.Continuation
    private let state = Mutex(State())

    init() {
        (events, continuation) = AsyncStream.makeStream(of: UploadEvent.self, bufferingPolicy: .unbounded)
    }

    var starts: [Start] { state.withLock { $0.starts } }
    var cancelled: [UUID] { state.withLock { $0.cancelled } }

    func setRunning(_ ids: Set<UUID>) {
        state.withLock { $0.running = ids }
    }

    func send(_ event: UploadEvent) {
        if case let .finished(itemID, _, _) = event {
            state.withLock { _ = $0.running.remove(itemID) }
        }
        continuation.yield(event)
    }

    func finish() {
        continuation.finish()
    }

    func start(
        itemID: UUID, deviceID: UUID, url: URL, bodyFile: URL, boundary: String, token: String, earliestBegin: Date?
    ) async {
        state.withLock {
            $0.starts.append(Start(
                itemID: itemID, deviceID: deviceID, url: url, token: token, earliestBegin: earliestBegin
            ))
            $0.running.insert(itemID)
        }
    }

    func runningItemIDs() async -> Set<UUID> {
        state.withLock { $0.running }
    }

    func cancel(itemID: UUID) async {
        state.withLock {
            $0.cancelled.append(itemID)
            $0.running.remove(itemID)
        }
    }
}
