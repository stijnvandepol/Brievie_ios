import Synchronization

final class LockedList: Sendable {
    private let mutex = Mutex<[String]>([])

    func append(_ value: String) {
        mutex.withLock { $0.append(value) }
    }

    var values: [String] { mutex.withLock { $0 } }
}
