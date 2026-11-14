import CryptoKit
import Foundation
import Security

public enum TrustError: Error, Equatable {
    case malformedCertificate
}

/// Turns the server's CA certificate into the fingerprint carried by the pairing QR code.
public enum CertificatePin {
    private static let beginMarker = "-----BEGIN CERTIFICATE-----"
    private static let endMarker = "-----END CERTIFICATE-----"

    /// DER bytes of the first certificate in `pem`.
    public static func der(fromPEM pem: String) throws(TrustError) -> Data {
        guard
            let begin = pem.range(of: beginMarker),
            let end = pem.range(of: endMarker, range: begin.upperBound..<pem.endIndex)
        else {
            throw .malformedCertificate
        }
        let base64 = pem[begin.upperBound..<end.lowerBound]
            .split(whereSeparator: \.isWhitespace)
            .joined()
        guard
            let der = Data(base64Encoded: base64),
            SecCertificateCreateWithData(nil, der as CFData) != nil
        else {
            throw .malformedCertificate
        }
        return der
    }

    /// SHA-256 of `der` in lower-case hex.
    public static func sha256Hex(ofDER der: Data) -> String {
        SHA256.hash(data: der)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
