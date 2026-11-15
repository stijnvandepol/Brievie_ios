import BrievieCore
import BrievieScan
import CoreGraphics
@testable import FeatureDocuments
import Foundation
import Testing

@MainActor
@Suite struct ScanFlowModelTests {
    private struct Recognizer: PageTextRecognizer {
        /// 1-based numbers of the pages whose recognition fails.
        var failing: Set<Int> = []
        let counter = LockedList()

        func text(in image: CGImage) async throws -> String {
            counter.append("call")
            let number = counter.values.count
            if failing.contains(number) { throw ScanError.recognitionFailed }
            return "tekst van pagina \(number)"
        }
    }

    private let queue = FakeUploadQueue()
    private let workspaceID = UUID()

    private func image(_ width: Int = 60, _ height: Int = 80) -> PageSource {
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ),
            let image = context.makeImage()
        else { fatalError("Cannot make a test image") }
        return .image(image)
    }

    private func model(_ recognizer: Recognizer = Recognizer()) -> ScanFlowModel {
        ScanFlowModel(workspaceID: workspaceID, uploads: queue, recognizer: recognizer)
    }

    @Test func pagesAreRecognisedEncodedAndQueuedInOrder() async {
        let model = model()

        await model.process([image(), image(), image()])

        #expect(model.phase == .finished)
        let pages = queue.enqueued.first ?? []
        #expect(pages.map(\.text) == ["tekst van pagina 1", "tekst van pagina 2", "tekst van pagina 3"])
        #expect(pages.allSatisfy { $0.jpeg.prefix(3) == Data([0xFF, 0xD8, 0xFF]) })
    }

    @Test func pageWithoutReadableTextIsKeptWithEmptyText() async {
        // Review Focus 5: a recogniser error on one page must not lose the scan.
        let model = model(Recognizer(failing: [2]))

        await model.process([image(), image(), image()])

        #expect(model.phase == .finished)
        #expect(queue.enqueued.first?.map(\.text) == ["tekst van pagina 1", "", "tekst van pagina 3"])
    }

    @Test func tooManyPagesAreRefusedBeforeAnyWork() async {
        // Review Focus 4
        let recognizer = Recognizer()
        let model = model(recognizer)

        await model.process(Array(repeating: image(), count: 31))

        #expect(model.phase == .failed(message: DocumentStrings.tooManyPages))
        #expect(recognizer.counter.values.isEmpty)
        #expect(queue.enqueued.isEmpty)
    }

    @Test func noPagesIsAMessageNotAnUpload() async {
        let model = model()

        await model.process([])

        #expect(model.phase == .failed(message: DocumentStrings.noPages))
        #expect(queue.enqueued.isEmpty)
    }

    @Test(arguments: [
        (UploadQueueError.diskFull, DocumentStrings.diskFull),
        (.tooLarge, DocumentStrings.tooLarge),
        (.tooManyPages, DocumentStrings.tooManyPages),
        (.writeFailed, DocumentStrings.scanFailed),
        (.noPages, DocumentStrings.noPages)
    ])
    func queueErrorsBecomeDutchMessages(error: UploadQueueError, message: String) async {
        queue.failEnqueue(with: error)
        let model = model()

        await model.process([image()])

        #expect(model.phase == .failed(message: message))
    }

    @Test func pageThatCannotBeDecodedStopsTheScanWithAMessage() async {
        let model = model()

        await model.process([image(), .encodedData(Data("geen afbeelding".utf8))])

        #expect(model.phase == .failed(message: DocumentStrings.unreadablePage))
        #expect(queue.enqueued.isEmpty)
    }

    @Test func progressNamesThePageBeingRead() {
        #expect(ScanFlowModel.Phase.recognising(page: 2, total: 5).label == "Tekst herkennen: pagina 2 van 5")
    }
}
