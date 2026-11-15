@testable import BrievieCore
import BrievieScan
import CryptoKit
import Foundation
import Testing

@Suite struct MultipartBodyWriterTests {
    private let clientID = UUID()
    private let boundary = "brievie-test-boundary"

    private func write(_ pages: [ScannedPage], maxText: Int = 20_000) throws -> (Data, Int64) {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).multipart")
        defer { try? FileManager.default.removeItem(at: file) }
        let count = try MultipartBodyWriter.write(
            clientID: clientID, pages: pages, boundary: boundary, maxTextCharacters: maxText, to: file
        )
        return (try Data(contentsOf: file), count)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @Test func metadataComesFirstThenThePagesInOrder() throws {
        let first = ScannedPage(jpeg: Data([0xFF, 0xD8, 0xFF, 1, 2, 3]), text: "Belastingdienst\nvóór 1 december")
        let second = ScannedPage(jpeg: Data([0xFF, 0xD8, 0xFF, 13, 10, 45, 45]), text: "")

        let (body, count) = try write([first, second])

        #expect(count == Int64(body.count))
        let parts = MultipartParser.parts(of: body, boundary: boundary)
        #expect(parts.map(\.name) == ["metadata", "page", "page"])
        #expect(parts[1].body == first.jpeg)
        #expect(parts[2].body == second.jpeg)
        #expect(parts[1].contentType == "image/jpeg")
        #expect(parts[1].filename == "1.jpg")
        #expect(parts[2].filename == "2.jpg")
        #expect(body.suffix(boundary.count + 6) == Data("--\(boundary)--\r\n".utf8))

        let metadata = try #require(JSONSerialization.jsonObject(with: parts[0].body) as? [String: Any])
        #expect(metadata["client_id"] as? String == clientID.uuidString.lowercased())
        let pages = try #require(metadata["pages"] as? [[String: String]])
        #expect(pages == [
            ["sha256": sha256(first.jpeg), "text": "Belastingdienst\nvóór 1 december"],
            ["sha256": sha256(second.jpeg), "text": ""]
        ])
    }

    @Test func tooLongPageTextIsCutNotRefused() throws {
        let page = ScannedPage(jpeg: Data([0xFF, 0xD8, 0xFF]), text: String(repeating: "é", count: 25_000))

        let (body, _) = try write([page])

        let parts = MultipartParser.parts(of: body, boundary: boundary)
        let metadata = try #require(JSONSerialization.jsonObject(with: parts[0].body) as? [String: Any])
        let pages = try #require(metadata["pages"] as? [[String: String]])
        #expect(pages[0]["text"]?.count == 20_000)
    }

    @Test func textIsCutByCodePointsAsTheHostCountsThem() throws {
        // "e" + combining acute: one Character, two code points. The host (Python) counts code points.
        let page = ScannedPage(jpeg: Data([0xFF, 0xD8, 0xFF]), text: String(repeating: "e\u{301}", count: 15_000))

        let (body, _) = try write([page])

        let parts = MultipartParser.parts(of: body, boundary: boundary)
        let metadata = try #require(JSONSerialization.jsonObject(with: parts[0].body) as? [String: Any])
        let pages = try #require(metadata["pages"] as? [[String: String]])
        let text = try #require(pages[0]["text"])
        #expect(text.unicodeScalars.count == 20_000)
        #expect(text.count == 10_000)
    }

    @Test func cutNeverSplitsACharacter() {
        // A family emoji is five code points joined into one Character.
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"

        let cut = MultipartBodyWriter.cut("ab" + family, maxCodePoints: 4)

        #expect(cut == "ab")
        #expect(MultipartBodyWriter.cut("ab" + family, maxCodePoints: 7) == "ab" + family)
        #expect(MultipartBodyWriter.cut("kort", maxCodePoints: 20_000) == "kort")
    }

    @Test func pageBytesThatLookLikeTheBoundaryStayIntact() throws {
        let tricky = Data([0xFF, 0xD8, 0xFF]) + Data("\r\n--not-the-boundary\r\n".utf8)

        let (body, _) = try write([ScannedPage(jpeg: tricky, text: "")])

        #expect(MultipartParser.parts(of: body, boundary: boundary)[1].body == tricky)
    }
}
