import Foundation
import Security

/// Decides whether a TLS server is the paired Brievie server.
///
/// With a CA certificate, only certificates issued by that CA are accepted (the system roots are ignored),
/// so the server can renew its leaf certificate without re-pairing. Without one, normal system trust applies.
public struct ServerTrust: Sendable {
    private let caCertificateDER: Data?

    /// - Parameter caCertificateDER: the paired server's CA certificate; `nil` uses system trust.
    public init(caCertificateDER: Data?) {
        self.caCertificateDER = caCertificateDER
    }

    public func evaluate(_ trust: SecTrust, host: String) -> Bool {
        guard SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess else {
            return false
        }
        if let caCertificateDER {
            guard
                let ca = SecCertificateCreateWithData(nil, caCertificateDER as CFData),
                SecTrustSetAnchorCertificates(trust, [ca] as CFArray) == errSecSuccess,
                SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess
            else {
                return false
            }
        }
        return SecTrustEvaluateWithError(trust, nil)
    }
}
