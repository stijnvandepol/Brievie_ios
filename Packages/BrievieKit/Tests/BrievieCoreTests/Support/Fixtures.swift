import BrievieCore
import Foundation
import Security
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

    static func der(_ name: String) throws -> Data {
        try CertificatePin.der(fromPEM: text(name))
    }

    /// A trust object for `leaf`, as a server would present it (leaf only, no chain), evaluated one day
    /// after the fixtures were issued so the tests do not expire with the 800-day leaves.
    static func serverTrust(leaf name: String) throws -> SecTrust {
        let certificate = try #require(SecCertificateCreateWithData(nil, try der(name) as CFData))
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust)
        #expect(status == errSecSuccess)
        let serverTrust = try #require(trust)
        #expect(SecTrustSetVerifyDate(serverTrust, try evaluationDate() as CFDate) == errSecSuccess)
        return serverTrust
    }
}
