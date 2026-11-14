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

    @Test func blankPageGivesEmptyTextNotAnError() async throws {
        // Review Focus 5
        let text = try await VisionTextRecognizer().text(in: TestImages.page(width: 800, height: 1000))

        #expect(text.isEmpty)
    }
}
