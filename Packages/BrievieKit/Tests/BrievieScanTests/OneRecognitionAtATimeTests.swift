@testable import BrievieScan
import Synchronization
import Testing

@Suite struct OneRecognitionAtATimeTests {
    final class Counter: Sendable {
        private let state = Mutex((running: 0, most: 0, done: 0))

        func start() { state.withLock { $0.running += 1; $0.most = max($0.most, $0.running) } }
        func finish() { state.withLock { $0.running -= 1; $0.done += 1 } }
        var most: Int { state.withLock { $0.most } }
        var done: Int { state.withLock { $0.done } }
    }

    @Test func onlyOneRecognitionRunsAtATime() async {
        let queue = RecognitionQueue()
        let counter = Counter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    await queue.enter()
                    counter.start()
                    await Task.yield()
                    counter.finish()
                    await queue.leave()
                }
            }
        }

        #expect(counter.most == 1)
        #expect(counter.done == 20)
    }
}
