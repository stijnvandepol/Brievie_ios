import Foundation

/// A small multipart/form-data reader for tests: enough to check what the app would upload.
struct MultipartPart: Equatable {
    let name: String
    let filename: String?
    let contentType: String?
    let body: Data
}

enum MultipartParser {
    static func parts(of data: Data, boundary: String) -> [MultipartPart] {
        let delimiter = Data("--\(boundary)".utf8)
        var parts: [MultipartPart] = []
        var cursor = data.startIndex
        var sections: [Data] = []
        while let range = data.range(of: delimiter, in: cursor..<data.endIndex) {
            if range.lowerBound > cursor { sections.append(data[cursor..<range.lowerBound]) }
            cursor = range.upperBound
        }
        for section in sections {
            // Each section is "\r\n<headers>\r\n\r\n<body>\r\n".
            guard let split = section.range(of: Data("\r\n\r\n".utf8)) else { continue }
            let headerBytes = section[section.startIndex..<split.lowerBound]
            guard let headers = String(bytes: headerBytes, encoding: .utf8) else { continue }
            let body = section[split.upperBound..<section.endIndex].dropLast(2)
            parts.append(MultipartPart(
                name: value(of: "name", in: headers) ?? "",
                filename: value(of: "filename", in: headers),
                contentType: headers.components(separatedBy: "\r\n")
                    .first { $0.lowercased().hasPrefix("content-type:") }?
                    .components(separatedBy: ": ").last,
                body: Data(body)
            ))
        }
        return parts
    }

    private static func value(of key: String, in headers: String) -> String? {
        guard let range = headers.range(of: "\(key)=\"") else { return nil }
        let rest = headers[range.upperBound...]
        // `name=` also matches inside `filename=`; take the standalone one.
        if key == "name", headers[..<range.lowerBound].hasSuffix("file") {
            return value(of: key, in: String(headers[..<range.lowerBound].dropLast(4)))
        }
        return rest.firstIndex(of: "\"").map { String(rest[..<$0]) }
    }
}
