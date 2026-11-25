import Foundation

/// The content of the pairing QR code shown by the server's web interface.
///
/// Wire format: `{"v":1,"urls":["https://…"],"code":"ABCD-EFGH","ca_sha256":"<64 hex>"|null}`.
public struct PairingPayload: Equatable, Sendable {
    /// Server addresses in server order: the local address first.
    public let urls: [URL]
    /// One-time pairing code, `XXXX-XXXX`.
    public let code: String
    /// SHA-256 of the server's CA certificate (DER) in lower-case hex; `nil` when the server uses a public certificate.
    public let caSHA256: String?
    /// The entries of `urls` the server serves with a public certificate (a tunnel); empty in a home QR. Only
    /// https entries of `urls` are kept (host PR #53: added to version 1, only when a public name exists).
    public let publicURLs: [URL]

    static let supportedVersion = 1

    public static func parse(_ qrText: String) throws(PairingPayloadError) -> PairingPayload {
        let data = Data(qrText.utf8)
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["v"] != nil
        else {
            throw .notBrievie
        }
        guard
            let probe = try? JSONDecoder().decode(VersionProbe.self, from: data),
            probe.v == supportedVersion
        else {
            throw .unsupportedVersion
        }
        guard let wire = try? JSONDecoder().decode(WirePayload.self, from: data) else {
            throw .invalid
        }
        return try PairingPayload(wire: wire)
    }

    private init(wire: WirePayload) throws(PairingPayloadError) {
        let urls = wire.urls.compactMap(Self.httpsURL(from:))
        guard !urls.isEmpty, urls.count == wire.urls.count else { throw .invalid }
        guard Self.isWellFormedCode(wire.code) else { throw .invalid }

        var caSHA256: String?
        if let hash = wire.caSHA256 {
            guard Self.isSHA256Hex(hash) else { throw .invalid }
            caSHA256 = hash.lowercased()
        }

        self.urls = urls
        self.code = wire.code
        self.caSHA256 = caSHA256
        self.publicURLs = ServerConnection.publicEntries(
            (wire.publicURLs ?? []).compactMap(Self.httpsURL(from:)), of: urls
        )
    }

    /// An `https` URL with a host and no user info; shared with `ServerLink`.
    static func httpsURL(from string: String) -> URL? {
        guard
            let url = URL(string: string),
            url.scheme?.lowercased() == "https",
            let host = url.host(), !host.isEmpty,
            url.user() == nil, url.password() == nil
        else {
            return nil
        }
        return url
    }

    /// `XXXX-XXXX`: two groups of four ASCII letters or digits.
    private static func isWellFormedCode(_ code: String) -> Bool {
        let bytes = Array(code.utf8)
        guard bytes.count == 9, bytes[4] == UInt8(ascii: "-") else { return false }
        return bytes.enumerated().allSatisfy { index, byte in
            index == 4 || isASCIIAlphanumeric(byte)
        }
    }

    static func isSHA256Hex(_ hash: String) -> Bool {
        hash.utf8.count == 64 && hash.utf8.allSatisfy(isASCIIHexDigit)
    }

    static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "A")...UInt8(ascii: "Z"):
            true
        default:
            false
        }
    }

    private static func isASCIIHexDigit(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "a")...UInt8(ascii: "f"),
             UInt8(ascii: "A")...UInt8(ascii: "F"):
            true
        default:
            false
        }
    }
}

public enum PairingPayloadError: Error, Equatable {
    /// Not JSON, or no `"v"`: some other QR code (a web link, a Wi-Fi code, random text).
    case notBrievie
    /// `"v"` is not a version this app understands.
    case unsupportedVersion
    /// Missing fields, no URLs, a non-https URL or one with user info, a malformed code or hash.
    case invalid
}

private struct VersionProbe: Decodable {
    let v: Int
}

private struct WirePayload: Decodable {
    let urls: [String]
    let code: String
    let caSHA256: String?
    let publicURLs: [String]?

    enum CodingKeys: String, CodingKey {
        case urls
        case code
        case caSHA256 = "ca_sha256"
        case publicURLs = "public_urls"
    }
}
