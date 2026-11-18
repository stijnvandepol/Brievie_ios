@testable import BrievieCore
import CryptoKit
import Foundation
import Testing

/// The proof matches the host's `apps/devices/proof.py` byte for byte, through the shared test vector.
@Suite struct PairingProofTests {
    /// SHA-256 of the host's `backend/tests/fixtures/pairing_proof_v1.json`. The copy here must be verbatim:
    /// an edit on either side shows up as a failure of `theFixtureIsTheHostsFile`.
    static let fixtureSHA256 = "ad19feccd3f7cc6b788afc1f3b0037c2e3deb8d27b0c74fbaa94a312decb24ff"

    struct VectorCase: Decodable {
        let trustBinding: String
        let proof: String
    }

    struct Vector: Decodable {
        let context: String
        let iterations: Int
        let typedCode: String
        let normalisedCode: String
        let pairingId: String
        let nonce: String
        let key: String
        let cases: [VectorCase]
    }

    static func vector() throws -> Vector {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Vector.self, from: Data(try Fixtures.text("pairing_proof_v1.json").utf8))
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    @Test func theFixtureIsTheHostsFile() throws {
        let url = try #require(Bundle.module.url(
            forResource: "pairing_proof_v1.json", withExtension: nil, subdirectory: "Fixtures"
        ))
        let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()

        #expect(digest == Self.fixtureSHA256)
    }

    @Test func proofMatchesTheSharedVector() throws {
        let vector = try Self.vector()
        let code = try #require(PairingCode(typed: vector.typedCode))
        let pairingID = try #require(UUID(uuidString: vector.pairingId))

        #expect(vector.context == PairingProof.context)
        #expect(vector.iterations == Int(PairingProof.iterations))
        #expect(code.normalised == vector.normalisedCode)
        let key = try #require(PairingProof.key(code: code, pairingID: pairingID))
        #expect(Self.hex(key) == vector.key)
        #expect(vector.cases.count == 2)
        for item in vector.cases {
            #expect(
                PairingProof.proof(key: key, nonce: vector.nonce, trustBinding: item.trustBinding) == item.proof,
                "binding \(item.trustBinding)"
            )
        }
    }

    @Test func thePairingIdIsLowerCasedForTheSalt() throws {
        let vector = try Self.vector()
        let code = try #require(PairingCode(typed: vector.typedCode))
        let upper = try #require(UUID(uuidString: vector.pairingId.uppercased()))

        #expect(PairingProof.key(code: code, pairingID: upper).map(Self.hex) == vector.key)
    }

    @Test @MainActor func theKeyIsDerivedOffTheMainActor() async throws {
        let vector = try Self.vector()
        let code = try #require(PairingCode(typed: vector.typedCode))
        let pairingID = try #require(UUID(uuidString: vector.pairingId))
        let finished = Locked(false)

        let item = try #require(vector.cases.first)
        let derivation = Task { @MainActor in
            let proof = await PairingProof.proof(
                code: code, pairingID: pairingID, nonce: vector.nonce, trustBinding: item.trustBinding
            )
            finished.value = true
            return proof
        }
        // Runs on the main actor; if the derivation held the main actor, this would only run after it.
        let mainWasFree = await Task { @MainActor in !finished.value }.value

        #expect(mainWasFree)
        #expect(await derivation.value == item.proof)
    }

    /// The proof's input `context + nonce + binding` has no length prefixes: it is unambiguous only because the
    /// nonce has a fixed length. With a shorter nonce a relay could move a character from the nonce into a
    /// look-alike host name (`N[..<42]` + `"c" + host` == `N` + `host` when `N` ends in "c").
    @Test func aNonceOfAnotherLengthOrAlphabetGetsNoProof() async throws {
        let vector = try Self.vector()
        let code = try #require(PairingCode(typed: vector.typedCode))
        let pairingID = try #require(UUID(uuidString: vector.pairingId))
        let key = try #require(PairingProof.key(code: code, pairingID: pairingID))
        let nonce = vector.nonce
        let illegal = String(nonce.dropLast()) + "+"

        #expect(nonce.count == 43)
        for bad in [String(nonce.dropLast()), nonce + "A", illegal, String(nonce.dropLast()) + "=", ""] {
            #expect(PairingProof.proof(key: key, nonce: bad, trustBinding: "brievie.example.nl") == nil, "\(bad)")
            #expect(await PairingProof.proof(
                code: code, pairingID: pairingID, nonce: bad,
                trustBinding: "brievie.example.nl"
            ) == nil)
        }
        #expect(PairingProof.isNonce(nonce))
        #expect(PairingProof.proof(key: key, nonce: nonce, trustBinding: "brievie.example.nl") != nil)
    }

    @Test func trustBindingIsThePinnedCertificate() throws {
        let der = try Fixtures.der("ca.pem")
        let url = try #require(URL(string: "https://brievie.example.nl"))

        let pinned = CertificatePin.sha256Hex(ofDER: der)
        #expect(PairingProof.trustBinding(caCertificateDER: der, connectedTo: url) == pinned)
    }

    @Test(arguments: [
        ("https://Brievie.Example.NL.:8443/x", "brievie.example.nl"),
        ("https://brievie.example.nl", "brievie.example.nl"),
        ("https://bücher.example.nl", "xn--bcher-kva.example.nl"),
        ("https://[2A00:1450:4001:082A:0000:0000:0000:200E]:8443", "2a00:1450:4001:82a::200e"),
        ("https://8.8.8.8", "8.8.8.8")
    ])
    func withoutAPinTheBindingIsTheHostName(url: String, binding: String) throws {
        let url = try #require(URL(string: url))

        #expect(PairingProof.trustBinding(caCertificateDER: nil, connectedTo: url) == binding)
    }

    @Test(arguments: [
        "https://brievie.local", "https://localhost", "https://nas", "https://nas.lan:8443", "https://nas.home.arpa",
        "https://192.168.1.4", "https://10.0.0.1", "https://127.0.0.1", "https://100.64.1.1",
        "https://[2001:db8::1]", "https://[fe80::1]", "https://[fd00::1]", "https://[::1]", "https://a.internal"
    ])
    func aHostNoPublicAuthorityCertifiesHasNoBindingWithoutAPin(url: String) throws {
        let url = try #require(URL(string: url))

        #expect(PairingProof.trustBinding(caCertificateDER: nil, connectedTo: url) == nil)
        // With the CA pin the same address binds to the pin.
        let der = try Fixtures.der("ca.pem")
        let pinned = CertificatePin.sha256Hex(ofDER: der)
        #expect(PairingProof.trustBinding(caCertificateDER: der, connectedTo: url) == pinned)
    }

    /// The host's `public_host_binding` on the same inputs (computed with Python 3.14's `ipaddress`).
    @Test(arguments: [
        ("Brievie.Example.NL.", "brievie.example.nl"), ("BRIEVIE.LOCAL", nil), ("localhost", nil),
        ("x.localhost", nil), ("nas", nil), ("a.test", nil), ("a.invalid", nil), ("a.example", nil), ("example", nil),
        ("local", nil), ("home.arpa", nil), ("a..b", nil), ("example.nl..", "example.nl"), ("[2001:db8::1]", nil),
        ("2001:4860:0:0:0:0:0:8888", "2001:4860::8888"), ("1:0:0:1:0:0:0:1", "1:0:0:1::1"),
        ("1:0:0:0:1:0:0:1", "1::1:0:0:1"), ("1:2:3:4:5:6:7:0", "1:2:3:4:5:6:7:0"),
        ("64:ff9b::808:808", "64:ff9b::808:808"), ("2002::1", nil), ("3fff::1", nil), ("192.0.0.9", "192.0.0.9"),
        ("0.0.0.0", nil), ("203.0.113.5", nil), ("1.1.1.1", "1.1.1.1"), ("169.254.1.1", nil),
        ("xn--bcher-kva.example.nl", "xn--bcher-kva.example.nl")
    ] as [(String, String?)])
    func mirrorsTheHostsPublicHostBinding(host: String, binding: String?) {
        #expect(PairingProof.publicHostBinding(host) == binding)
    }

    /// Where the host would bind but the app is stricter: such an address simply cannot pair by link.
    @Test(arguments: ["::ffff:8.8.8.8", "224.0.0.1", "ff02::1", "192.168.001.4", "fe80::1%en0"])
    func theAppIsStricterWhereTheSidesCouldDisagree(host: String) {
        #expect(PairingProof.publicHostBinding(host) == nil)
    }
}
