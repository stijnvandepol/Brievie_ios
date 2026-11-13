@testable import BrievieCore
import Foundation
import Testing

@Suite struct CertificatePinTests {
    @Test func hashOfCAMatchesOpenSSL() throws {
        let der = try CertificatePin.der(fromPEM: Fixtures.text("ca.pem"))
        let expected = try Fixtures.text("ca.sha256").trimmingCharacters(in: .whitespacesAndNewlines)

        #expect(CertificatePin.sha256Hex(ofDER: der) == expected)
    }

    @Test func hashIsLowerCaseHex() throws {
        let hex = CertificatePin.sha256Hex(ofDER: Data([0xAB, 0xCD]))

        #expect(hex.count == 64)
        #expect(hex == hex.lowercased())
    }

    @Test func differentCertificatesHaveDifferentHashes() throws {
        let ca = try CertificatePin.der(fromPEM: Fixtures.text("ca.pem"))
        let other = try CertificatePin.der(fromPEM: Fixtures.text("other-ca.pem"))

        #expect(CertificatePin.sha256Hex(ofDER: ca) != CertificatePin.sha256Hex(ofDER: other))
    }

    @Test(arguments: [
        "",
        "not a certificate",
        "-----BEGIN CERTIFICATE-----\n-----END CERTIFICATE-----\n",
        "-----BEGIN CERTIFICATE-----\naGVsbG8gd29ybGQ=\n-----END CERTIFICATE-----\n",
        "-----BEGIN CERTIFICATE-----\n!!!not base64!!!\n-----END CERTIFICATE-----\n"
    ])
    func garbagePEMIsMalformed(pem: String) {
        #expect(throws: TrustError.malformedCertificate) {
            try CertificatePin.der(fromPEM: pem)
        }
    }
}
