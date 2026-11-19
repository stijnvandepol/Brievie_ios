import BrievieScan
import CoreGraphics
import Foundation
import Synchronization
import Testing

/// The page pipeline with a scripted recogniser: it "reads" the black mark of `TestImages.marked` as the
/// start of the text, so a mark top-left is an upright page. Runs everywhere, no Vision.
@Suite struct PageProcessorTests {
    final class MarkReader: PageTextRecognizer {
        /// The corner the mark was in, per call.
        let seen = Mutex<[TestImages.Corner?]>([])
        let characters: Int
        let fails: Bool

        init(characters: Int = 40, fails: Bool = false) {
            self.characters = characters
            self.fails = fails
        }

        func lines(in image: CGImage) async throws -> [RecognizedLine] {
            let corner = TestImages.darkCorner(of: image)
            seen.withLock { $0.append(corner) }
            if fails { throw ScanError.recognitionFailed }
            let (along, rise): (Double, Double) = switch corner {
            case .topLeft, nil: (500, 0)
            case .topRight: (0, -500)  // turned a quarter clockwise: the lines run down
            case .bottomRight: (-500, 0)
            case .bottomLeft: (0, 500)
            }
            let text = "gelezen " + String(repeating: "x", count: characters)
            return [RecognizedLine(text: text, confidence: 1, baselineX: along, baselineY: rise)]
        }

        var calls: [TestImages.Corner?] { seen.withLock { $0 } }
    }

    private func page(_ corner: TestImages.Corner) -> PageSource {
        .image(TestImages.marked(width: 300, height: 400, corner: corner))
    }

    private func uploadedCorner(_ page: ProcessedPage) throws -> TestImages.Corner? {
        TestImages.darkCorner(of: try #require(TestImages.storedPixels(ofJPEG: page.page.jpeg)))
    }

    @Test func anUprightPageIsReadOnce() async throws {
        let reader = MarkReader()

        let result = try await PageProcessor(recognizer: reader).process(page(.topLeft))

        #expect(reader.calls == [.topLeft])
        #expect(result.turn == .upright)
        #expect(!result.turnedAutomatically)
        #expect(try uploadedCorner(result) == .topLeft)
    }

    @Test(arguments: [
        (TestImages.Corner.topRight, QuarterTurn.counterClockwise), (.bottomRight, .upsideDown),
        (.bottomLeft, .clockwise)
    ])
    func aTurnedPageIsTurnedUprightAndReadAgain(corner: TestImages.Corner, turn: QuarterTurn) async throws {
        let reader = MarkReader()

        let result = try await PageProcessor(recognizer: reader).process(page(corner))

        // The kept text is the second reading, of the upright page.
        #expect(reader.calls == [corner, .topLeft])
        #expect(result.turn == turn)
        #expect(result.turnedAutomatically)
        #expect(try uploadedCorner(result) == .topLeft)
        let preview = try #require(TestImages.storedPixels(ofJPEG: result.preview))
        #expect(TestImages.darkCorner(of: preview) == .topLeft)
        #expect(preview.height == (turn.swapsSides ? 300 : 400))
    }

    @Test func aTurnChosenByTheUserIsAppliedAsItIsAndNotCorrected() async throws {
        let reader = MarkReader()

        let result = try await PageProcessor(recognizer: reader).process(page(.topLeft), turn: .clockwise)

        #expect(reader.calls == [.topRight])
        #expect(result.turn == .clockwise)
        #expect(!result.turnedAutomatically)
        #expect(try uploadedCorner(result) == .topRight)
        #expect(result.page.text.hasPrefix("gelezen"))
    }

    @Test func aPageWithTooLittleTextStaysAsItIs() async throws {
        let reader = MarkReader(characters: 1)

        let result = try await PageProcessor(recognizer: reader).process(page(.bottomRight))

        #expect(reader.calls == [.bottomRight])
        #expect(result.turn == .upright)
        #expect(try uploadedCorner(result) == .bottomRight)
    }

    @Test func aPageTheRecogniserCannotReadIsKeptWithoutText() async throws {
        let reader = MarkReader(fails: true)

        let result = try await PageProcessor(recognizer: reader).process(page(.bottomRight))

        #expect(result.page.text.isEmpty)
        #expect(result.turn == .upright)
        #expect(result.page.jpeg.prefix(3) == Data([0xFF, 0xD8, 0xFF]))
    }

    @Test func aPageThatIsNotAnImageIsRefused() async {
        await #expect(throws: ScanError.encodingFailed) {
            try await PageProcessor(recognizer: MarkReader()).process(.encodedData(Data("geen afbeelding".utf8)))
        }
    }

    @Test func aCancelledScanStopsBeforeReading() async {
        let reader = MarkReader()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await PageProcessor(recognizer: reader).process(page(.topLeft))
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(reader.calls.isEmpty)
    }
}
