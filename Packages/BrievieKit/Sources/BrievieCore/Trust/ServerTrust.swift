import Foundation
import Security

/// Decides whether a TLS server is the paired Brievie server.
///
/// With a CA certificate, only certificates issued by that CA are accepted (the system roots are ignored),
/// so the server can renew its leaf certificate without re-pairing. Without one, normal system trust applies.
///
/// Per address (external access, host PR #53): a host in `publicHosts` is one the server itself said carries a
/// public certificate (a tunnel); it gets the system roots and the host name check, never the CA. Every other
/// host stays anchored to the CA alone.
public struct ServerTrust: Sendable {
    private let caCertificateDER: Data?
    private let publicHosts: Set<String>

    /// - Parameters:
    ///   - caCertificateDER: the paired server's CA certificate; `nil` uses system trust.
    ///   - publicHosts: the hosts of the server's own `public_urls`, received over a CA-pinned connection.
    public init(caCertificateDER: Data?, publicHosts: Set<String> = []) {
        self.caCertificateDER = caCertificateDER
        self.publicHosts = Set(publicHosts.map { $0.lowercased() })
    }

    public func evaluate(_ trust: SecTrust, host: String) -> Bool {
        guard SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess else {
            return false
        }
        if let caCertificateDER, !publicHosts.contains(host.lowercased()) {
            guard
                let ca = SecCertificateCreateWithData(nil, caCertificateDER as CFData),
                SecTrustSetAnchorCertificates(trust, [ca] as CFArray) == errSecSuccess,
                // Defence in depth: setting anchors already disables all other anchors (Apple docs), so this
                // call does not change behaviour and cannot be covered by a test. It is kept deliberately so
                // the intent stays explicit and survives a future change to how anchors are set.
                SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess
            else {
                return false
            }
        }
        return SecTrustEvaluateWithError(trust, nil)
    }
}
