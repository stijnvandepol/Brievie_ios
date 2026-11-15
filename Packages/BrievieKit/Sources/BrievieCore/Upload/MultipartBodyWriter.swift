import BrievieAPI
import BrievieScan
import CryptoKit
import Foundation

/// Writes a scan as the `multipart/form-data` body of `createDocument`, ready to upload from a file.
///
/// Layout (host contract): the field `metadata` (JSON of `UploadMetadataIn`), then one `page` file per page
/// in page order.
public enum MultipartBodyWriter {
    /// - Returns: the number of bytes written.
    public static func write(
        clientID: UUID, pages: [ScannedPage], boundary: String, maxTextCharacters: Int, to file: URL
    ) throws -> Int64 {
        let metadata = Components.Schemas.UploadMetadataIn(
            clientId: clientID.uuidString.lowercased(),
            pages: pages.map { page in
                .init(sha256: sha256Hex(page.jpeg), text: cut(page.text, maxCodePoints: maxTextCharacters))
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        var body = Data()
        body.append(part(boundary, #"name="metadata""#, contentType: nil))
        body.append(try encoder.encode(metadata))
        body.append(Data("\r\n".utf8))
        for (index, page) in pages.enumerated() {
            body.append(part(boundary, #"name="page"; filename="\#(index + 1).jpg""#, contentType: "image/jpeg"))
            body.append(page.jpeg)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        try body.write(to: file, options: .atomic)
        return Int64(body.count)
    }

    /// The longest start of `text` with at most `maxCodePoints` Unicode code points: the host counts code
    /// points, not `Character`s. Cut between whole characters, so a letter with its accent or a joined emoji
    /// is never split.
    static func cut(_ text: String, maxCodePoints: Int) -> String {
        guard text.unicodeScalars.count > maxCodePoints else { return text }
        var count = 0
        var end = text.startIndex
        for character in text {
            count += character.unicodeScalars.count
            if count > maxCodePoints { break }
            end = text.index(after: end)
        }
        return String(text[..<end])
    }

    /// The value of the request's `Content-Type` header for a body written with `boundary`.
    public static func contentType(boundary: String) -> String {
        "multipart/form-data; boundary=\(boundary)"
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func part(_ boundary: String, _ disposition: String, contentType: String?) -> Data {
        var header = "--\(boundary)\r\nContent-Disposition: form-data; \(disposition)\r\n"
        if let contentType {
            header += "Content-Type: \(contentType)\r\n"
        }
        return Data((header + "\r\n").utf8)
    }
}
