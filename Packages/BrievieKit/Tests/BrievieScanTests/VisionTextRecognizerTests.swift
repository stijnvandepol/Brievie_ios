import BrievieScan
import CoreGraphics
import Foundation
import ImageIO
import Testing

@Suite struct VisionTextRecognizerTests {
    private func fixture(_ name: String) throws -> CGImage {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Fixtures"))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    @Test func readsADutchLetterInReadingOrder() async throws {
        let text = try await VisionTextRecognizer().text(in: fixture("letter-nl"))

        #expect(text.contains("Belastingdienst"))
        #expect(text.contains("1 december 2026"))
        let lines = text.split(separator: "\n").map(String.init)
        let sender = try #require(lines.firstIndex { $0.contains("Belastingdienst") })
        let date = try #require(lines.firstIndex { $0.contains("3 november 2026") })
        let deadline = try #require(lines.firstIndex { $0.contains("1 december 2026") })
        #expect(sender < date)
        #expect(date < deadline)
    }

    @Test(arguments: QuarterTurn.allCases)
    func theDirectionOfTheLinesShowsHowThePageIsTurned(turn: QuarterTurn) async throws {
        // Vision (revision 3) reads a turned page too, with each line's corners in the turned image.
        let turned = try PageImageEncoder.rotated(fixture("letter-nl"), by: turn)

        let lines = try await VisionTextRecognizer().lines(in: turned)

        #expect(lines.contains { $0.text.contains("Belastingdienst") })
        // Turning back undoes the turn: four quarters in all.
        #expect(PageOrientation.correction(for: lines).map(turn.adding) == .upright)
    }

    @Test func aTurnedPageIsReadInOrderOnlyAfterItIsTurnedUpright() async throws {
        let turned = try PageImageEncoder.rotated(fixture("letter-nl"), by: .clockwise)
        let source = PageSource.encodedData(try PageImageEncoder.jpeg(from: turned))

        let page = try await PageProcessor().process(source)

        #expect(page.turn == .counterClockwise)
        #expect(page.turnedAutomatically)
        let lines = page.page.text.split(separator: "\n").map(String.init)
        let sender = try #require(lines.firstIndex { $0.contains("Belastingdienst") })
        let date = try #require(lines.firstIndex { $0.contains("3 november 2026") })
        let deadline = try #require(lines.firstIndex { $0.contains("1 december 2026") })
        #expect(sender < date)
        #expect(date < deadline)
    }

    @Test func blankPageGivesEmptyTextNotAnError() async throws {
        // Review Focus 5
        let text = try await VisionTextRecognizer().text(in: TestImages.page(width: 800, height: 1000))

        #expect(text.isEmpty)
    }
}
