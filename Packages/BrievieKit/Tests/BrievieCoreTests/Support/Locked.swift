import Synchronization

/// A value behind a lock that can be shared with `@Sendable` closures in tests.
final class Locked<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>

    init(_ value: Value) {
        mutex = Mutex(value)
    }

    var value: Value {
        get { mutex.withLock { $0 } }
        set { mutex.withLock { $0 = newValue } }
    }

    func update(_ change: @Sendable (inout Value) -> Void) {
        mutex.withLock { change(&$0) }
    }
}
