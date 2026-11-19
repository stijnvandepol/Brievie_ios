import BrievieCore
import BrievieScan
import CoreGraphics
@testable import FeatureDocuments
import Foundation
import ImageIO
import Testing

@MainActor
@Suite struct ScanFlowModelTests {
    /// Reads "tekst van pagina N" in call order. A landscape image reads as a page turned a quarter clockwise
    /// (its lines run down), so the automatic step turns it back to portrait.
    struct Recognizer: PageTextRecognizer {
        /// 1-based numbers of the calls that fail.
        var failing: Set<Int> = []
        let counter = LockedList()

        func lines(in image: CGImage) async throws -> [RecognizedLine] {
            counter.append("call")
            let number = counter.values.count
            if failing.contains(number) { throw ScanError.recognitionFailed }
            let landscape = image.width > image.height
            return [
                RecognizedLine(
                    text: "tekst van pagina \(number)", confidence: 1,
                    baselineX: landscape ? 0 : 100, baselineY: landscape ? -100 : 0
                )
            ]
        }
    }

    let queue = FakeUploadQueue()
    private let workspaceID = UUID()

    func image(_ width: Int = 60, _ height: Int = 80) -> PageSource {
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

    func model(_ recognizer: any PageTextRecognizer = Recognizer()) -> ScanFlowModel {
        ScanFlowModel(workspaceID: workspaceID, uploads: queue, recognizer: recognizer)
    }

    static func size(_ jpeg: Data) -> (Int, Int)? {
        guard
            let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return (image.width, image.height)
    }

    @Test func pagesWaitForTheUserBeforeTheyAreQueued() async {
        let model = model()

        await model.process([image(), image(), image()])

        #expect(model.phase == .reviewing)
        #expect(model.isPresented)
        #expect(model.pages.map(\.id) == [0, 1, 2])
        #expect(queue.enqueued.isEmpty)
    }

    @Test func savingQueuesThePagesInOrder() async {
        let model = model()
        await model.process([image(), image(), image()])

        await model.save()

        #expect(model.phase == .finished)
        #expect(!model.isPresented)
        #expect(model.pages.isEmpty)
        let pages = queue.enqueued.first ?? []
        #expect(pages.map(\.text) == ["tekst van pagina 1", "tekst van pagina 2", "tekst van pagina 3"])
        #expect(pages.allSatisfy { $0.jpeg.prefix(3) == Data([0xFF, 0xD8, 0xFF]) })
    }

    @Test func pageWithoutReadableTextIsKeptWithEmptyText() async {
        // Review Focus 5: a recogniser error on one page must not lose the scan.
        let model = model(Recognizer(failing: [2]))

        await model.process([image(), image(), image()])
        await model.save()

        #expect(model.phase == .finished)
        #expect(queue.enqueued.first?.map(\.text) == ["tekst van pagina 1", "", "tekst van pagina 3"])
    }

    @Test func aTurnedPageIsTurnedUprightAutomaticallyAndMarked() async {
        let recognizer = Recognizer()
        let model = model(recognizer)

        await model.process([image(), image(80, 60)])
        await model.save()

        #expect(model.phase == .finished)
        let pages = queue.enqueued.first ?? []
        #expect(pages.compactMap { Self.size($0.jpeg) }.map(\.0) == [60, 60])
        // Read once as it came in, once upright: the second reading is the text that is kept.
        #expect(pages.map(\.text) == ["tekst van pagina 1", "tekst van pagina 3"])
        #expect(recognizer.counter.values.count == 3)
    }

    @Test func turningAPageByHandTurnsItAQuarterAndReadsItAgain() async {
        let recognizer = Recognizer()
        let model = model(recognizer)
        await model.process([image(), image()])

        await model.turn(page: 1)

        #expect(model.pages[1].isTurning == false)
        #expect(Self.size(model.pages[1].preview).map(\.0) == 80)
        await model.save()
        let pages = queue.enqueued.first ?? []
        #expect(pages.compactMap { Self.size($0.jpeg) }.map(\.0) == [60, 80])
        // The landscape result is not turned back: the user chose it.
        #expect(pages.map(\.text) == ["tekst van pagina 1", "tekst van pagina 3"])
    }

    @Test func turningByHandUndoesAnAutomaticTurn() async {
        let model = model()
        await model.process([image(80, 60)])
        #expect(model.pages.first?.turnedAutomatically == true)

        await model.turn(page: 0)

        // The automatic step turned it counter-clockwise; one turn clockwise is the page as it came in.
        #expect(model.pages.first?.turnedAutomatically == false)
        #expect(model.pages.first.flatMap { Self.size($0.preview) }.map(\.0) == 80)
    }

    @Test func fourTurnsBringThePageBack() async {
        let model = model()
        await model.process([image()])

        for _ in 0..<4 { await model.turn(page: 0) }
        await model.save()

        #expect(queue.enqueued.first?.first.flatMap { Self.size($0.jpeg) }.map(\.0) == 60)
    }

    @Test func discardingForgetsTheScan() async {
        let model = model()
        await model.process([image(), image()])

        model.discard()

        #expect(model.phase == .idle)
        #expect(model.pages.isEmpty)
        await model.save()
        #expect(queue.enqueued.isEmpty)
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

        await model.save()

        #expect(model.phase == .failed(message: message))
    }

    @Test func pageThatCannotBeDecodedStopsTheScanWithAMessage() async {
        let model = model()

        await model.process([image(), .encodedData(Data("geen afbeelding".utf8))])

        #expect(model.phase == .failed(message: DocumentStrings.unreadablePage))
        #expect(model.pages.isEmpty)
        #expect(queue.enqueued.isEmpty)
    }

    @Test func pageThatCouldNotBeLoadedStopsTheScanInsteadOfBeingDropped() async {
        // Final review: a photo that is only in iCloud, or a scanner page without data, must not vanish:
        // a three-page letter would be uploaded as two pages without a word.
        let model = model()

        await model.process(loaded: [image(), nil, image()])

        #expect(model.phase == .failed(message: DocumentStrings.unreadablePage))
        #expect(queue.enqueued.isEmpty)
    }

    @Test func completelyLoadedPagesAreProcessed() async {
        let model = model()

        await model.process(loaded: [image(), image()])

        #expect(model.phase == .reviewing)
        #expect(model.pages.count == 2)
    }

    @Test func progressNamesThePageBeingRead() {
        #expect(ScanFlowModel.Phase.recognising(page: 2, total: 5).label == "Tekst herkennen: pagina 2 van 5")
    }
}
