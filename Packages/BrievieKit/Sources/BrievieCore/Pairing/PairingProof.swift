import CommonCrypto
import CryptoKit
import Foundation

/// Pairing from a link by proof, protocol version 1 (D 6.2 as changed by D 20; host `apps/devices/proof.py`).
///
/// The phone never sends the typed code. It sends
///
///     proof = HMAC-SHA256(key, "brievie-pair-v1" || nonce || trust binding)   (lower-case hex)
///     key   = PBKDF2-HMAC-SHA256(normalised code, "brievie-pair-v1" || pairing id, 600,000, 32)
///
/// where the trust binding is what TLS validated for this connection: the SHA-256 of the CA certificate the
/// app pinned, or, for a connection validated by the system roots, the host name it connected to. A relay with
/// another certificate or host gets a proof the real server refuses, and never sees the code.
/// `Tests/Fixtures/pairing_proof_v1.json` is the host's test vector, copied verbatim. Never change a constant
/// here: that is a version 2 on both sides.
public enum PairingProof {
    static let context = "brievie-pair-v1"
    static let iterations: UInt32 = 600_000
    static let keyLength = 32

    /// The host's nonces are `secrets.token_urlsafe(32)`: exactly 43 characters of the base64url alphabet.
    static let nonceLength = 43

    /// Whether `nonce` is one the host makes. The proof's input `context + nonce + binding` has no length
    /// prefixes; it is unambiguous only because the nonce has this fixed length. A shorter nonce would let a
    /// relay move characters between the nonce and a look-alike host name, so no proof is made for one.
    static func isNonce(_ nonce: String) -> Bool {
        nonce.utf8.count == nonceLength && nonce.utf8.allSatisfy { byte in
            PairingPayload.isASCIIAlphanumeric(byte) || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "_")
        }
    }

    /// PBKDF2-HMAC-SHA256 of `code.normalised`, salted with the context and the pairing id in lower-case
    /// hyphenated form, as `Data` (for the shared test vector). Pairing uses `proof(code:pairingID:nonce:trustBinding:)`,
    /// which never lets the key out of its own buffer. `nil` only if CommonCrypto fails.
    static func key(code: PairingCode, pairingID: UUID) -> Data? {
        var key = [UInt8](repeating: 0, count: keyLength)
        defer { wipe(&key) }
        guard derive(code: code, pairingID: pairingID, into: &key) else { return nil }
        return Data(key)
    }

    /// The proof for `nonce` and `trustBinding`, the key derived (slow on purpose, about half a second) off the
    /// caller's actor whatever the default isolation, and wiped before returning. `nil` for a nonce that is not
    /// `isNonce` (nothing is derived then) or if CommonCrypto fails.
    @concurrent
    static func proof(code: PairingCode, pairingID: UUID, nonce: String, trustBinding: String) async -> String? {
        guard isNonce(nonce) else { return nil }
        var key = [UInt8](repeating: 0, count: keyLength)
        defer { wipe(&key) }
        guard derive(code: code, pairingID: pairingID, into: &key) else { return nil }
        // `SymmetricKey` keeps its own copy in CryptoKit's secure storage, zeroed when it is released.
        return mac(SymmetricKey(data: key), nonce: nonce, trustBinding: trustBinding)
    }

    /// Lower-case hex of HMAC-SHA256(key, context + nonce + trust binding); `nil` for a nonce that is not
    /// `isNonce`, so the rule never depends on the caller.
    static func proof(key: Data, nonce: String, trustBinding: String) -> String? {
        guard isNonce(nonce) else { return nil }
        return mac(SymmetricKey(data: key), nonce: nonce, trustBinding: trustBinding)
    }

    private static func mac(_ key: SymmetricKey, nonce: String, trustBinding: String) -> String {
        let message = Data((context + nonce + trustBinding).utf8)
        return HMAC<SHA256>.authenticationCode(for: message, using: key).map { String(format: "%02x", $0) }.joined()
    }

    private static func derive(code: PairingCode, pairingID: UUID, into key: inout [UInt8]) -> Bool {
        let password = Array(code.normalised.utf8)
        let salt = Array((context + pairingID.uuidString.lowercased()).utf8)
        let count = key.count
        let status = password.withUnsafeBufferPointer { passwordBytes in
            passwordBytes.withMemoryRebound(to: CChar.self) { passwordChars in
                key.withUnsafeMutableBufferPointer { keyBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordChars.baseAddress, passwordChars.count,
                        salt, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        keyBytes.baseAddress, count
                    )
                }
            }
        }
        return status == kCCSuccess
    }

    /// Overwrites `bytes` with zeros in a way the optimiser does not remove (`memset_s`).
    private static func wipe(_ bytes: inout [UInt8]) {
        bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = memset_s(base, buffer.count, 0, buffer.count)
        }
    }

    /// What TLS validated for a connection to `url`: the SHA-256 of `caCertificateDER` when the app pinned that
    /// CA (the certificate actually anchored, never the link's text), else the host name (`publicHostBinding`).
    /// `nil` when neither applies: such a connection cannot pair by proof.
    static func trustBinding(caCertificateDER: Data?, connectedTo url: URL) -> String? {
        if let caCertificateDER { return CertificatePin.sha256Hex(ofDER: caCertificateDER) }
        return publicHostBinding(of: url)
    }

    /// The host binding of `url` as the app contacts it (the ASCII, IDNA form of its host).
    static func publicHostBinding(of url: URL) -> String? {
        guard let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.encodedHost else { return nil }
        return publicHostBinding(host)
    }
}
