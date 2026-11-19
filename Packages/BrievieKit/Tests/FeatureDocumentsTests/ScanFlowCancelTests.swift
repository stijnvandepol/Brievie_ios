import BrievieScan
import CoreGraphics
@testable import FeatureDocuments
import Foundation
import Testing

/// Throwing a scan away while its pages are still being read.
@MainActor
@Suite struct ScanFlowCancelTests {
    /// Holds every reading until `release()`.
    final class GateRecognizer: PageTextRecognizer {
        let calls = LockedList()
        private let gate = AsyncStream.makeStream(of: Void.self)

        func lines(in image: CGImage) async throws -> [RecognizedLine] {
            calls.append("call")
            for await _ in gate.stream { break }
            return [RecognizedLine(text: "tekst", confidence: 1, baselineX: 1, baselineY: 0)]
        }

        func release() {
            gate.continuation.yield(())
        }
    }

    @Test func discardingWhileReadingStopsBeforeTheNextPage() async {
        let recognizer = GateRecognizer()
        let queue = FakeUploadQueue()
        let model = ScanFlowModel(workspaceID: UUID(), uploads: queue, recognizer: recognizer)
        let page = ScanFlowModelTests().image()

        model.start(loaded: [page, page, page])
        #expect(model.isPresented)
        while recognizer.calls.values.isEmpty { await Task.yield() }
        let work = model.work
        model.discard()
        recognizer.release()
        await work?.value

        #expect(model.phase == .idle)
        #expect(model.pages.isEmpty)
        #expect(recognizer.calls.values.count == 1)
        #expect(queue.enqueued.isEmpty)
    }
}
