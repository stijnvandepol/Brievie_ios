import Foundation
import Testing

/// Test certificates from `Tests/Fixtures` (see `make-certs.sh`).
enum Fixtures {
    static func text(_ name: String) throws -> String {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"),
            "Missing fixture \(name)"
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// One day after the certificates were issued: inside every fixture's validity period.
    static func evaluationDate() throws -> Date {
        let issuedAt = try text("issued-at").trimmingCharacters(in: .whitespacesAndNewlines)
        let date = try #require(ISO8601DateFormatter().date(from: issuedAt), "Bad issued-at: \(issuedAt)")
        return date.addingTimeInterval(24 * 60 * 60)
    }
}
