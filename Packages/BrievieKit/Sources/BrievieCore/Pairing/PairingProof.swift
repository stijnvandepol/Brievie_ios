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

    /// PBKDF2-HMAC-SHA256 of `code.normalised`, salted with the context and the pairing id in lower-case
    /// hyphenated form. Slow on purpose (about half a second): call `derivedKey` from async code.
    /// `nil` only if CommonCrypto fails.
    static func key(code: PairingCode, pairingID: UUID) -> Data? {
        let password = Array(code.normalised.utf8)
        let salt = Array((context + pairingID.uuidString.lowercased()).utf8)
        var key = [UInt8](repeating: 0, count: keyLength)
        let status = password.withUnsafeBufferPointer { passwordBytes in
            passwordBytes.withMemoryRebound(to: CChar.self) { passwordChars in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordChars.baseAddress, passwordChars.count,
                    salt, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    &key, key.count
                )
            }
        }
        guard status == kCCSuccess else { return nil }
        return Data(key)
    }

    /// `key(code:pairingID:)` off the caller's actor: a nonisolated async function runs on the global
    /// executor, so the main actor stays free while the key is derived.
    static func derivedKey(code: PairingCode, pairingID: UUID) async -> Data? {
        key(code: code, pairingID: pairingID)
    }

    /// Lower-case hex of HMAC-SHA256(key, context + nonce + trust binding).
    static func proof(key: Data, nonce: String, trustBinding: String) -> String {
        let message = Data((context + nonce + trustBinding).utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key))
        return mac.map { String(format: "%02x", $0) }.joined()
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
