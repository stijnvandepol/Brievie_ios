import Foundation

public enum ServerLinkError: Error, Equatable {
    /// Not a `brievie://server` link (a task link, another app's link).
    case notAServerLink
    /// A link of a newer link version than this app reads.
    case unsupportedVersion
    /// Missing or repeated fields, a bad address, pin or pairing id, a malformed escape, or too long.
    case invalid
}

/// The link on the server's pairing page that opens the app (D 6.2, D 20):
/// `brievie://server#v=1&url=<https url>[&url=…][&ca_sha256=<64 hex>]&pairing=<uuid>`, values form-encoded.
///
/// It is only a pointer: the server's addresses, its CA pin and the id of a pairing code. It carries no secret,
/// and a code smuggled into it is never read: the user types the code, and on this path it never leaves the
/// phone (`PairingService.pair(link:code:deviceName:)`).
public struct ServerLink: Equatable, Sendable {
    /// `https` only, in server order, one to eight.
    public let urls: [URL]
    /// SHA-256 of the server's CA certificate in lower-case hex; `nil` for a server with a public certificate.
    public let caSHA256: String?
    /// The pairing code's id on the server. Not secret: it names the code for a proof but cannot redeem it.
    public let pairingID: UUID

    static let supportedVersion = "1"
    static let maximumFragmentLength = 4096
    static let maximumURLs = 8
    static let maximumURLLength = 2048

    /// `brievie://server…` (scheme and host in any case); nothing else.
    public static func isServerLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "brievie" && url.host(percentEncoded: true)?.lowercased() == "server"
    }

    /// Reads the link under the rules of the pairing QR code. A path or query on the link is ignored, as is
    /// every key it does not know (`code` included).
    public static func parse(_ url: URL) throws(ServerLinkError) -> ServerLink {
        guard isServerLink(url) else { throw .notAServerLink }
        guard
            let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment,
            fragment.utf8.count <= maximumFragmentLength
        else {
            throw .invalid
        }
        var fields: [String: [String]] = [:]
        for pair in fragment.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(parts[0])
            guard ["v", "url", "ca_sha256", "pairing"].contains(key) else { continue }
            let raw = parts.count == 2 ? String(parts[1]) : ""
            fields[key, default: []].append(try formDecoded(raw))
        }
        return try ServerLink(fields: fields)
    }

    private init(fields: [String: [String]]) throws(ServerLinkError) {
        guard let versions = fields["v"], versions.count == 1 else { throw .invalid }
        if versions[0] != Self.supportedVersion {
            throw Int(versions[0]) == nil ? .invalid : .unsupportedVersion
        }

        let texts = fields["url"] ?? []
        guard (1...Self.maximumURLs).contains(texts.count) else { throw .invalid }
        var urls: [URL] = []
        for text in texts {
            guard
                text.utf8.count <= Self.maximumURLLength,
                !text.unicodeScalars.contains(where: Self.isSpaceOrControl),
                let url = PairingPayload.httpsURL(from: text)
            else {
                throw .invalid
            }
            urls.append(url)
        }

        let pins = fields["ca_sha256"] ?? []
        guard pins.count <= 1 else { throw .invalid }
        if let pin = pins.first, !PairingPayload.isSHA256Hex(pin) { throw .invalid }

        guard
            let ids = fields["pairing"], ids.count == 1,
            let pairingID = UUID(uuidString: ids[0])
        else {
            throw .invalid
        }

        self.urls = urls
        caSHA256 = pins.first?.lowercased()
        self.pairingID = pairingID
    }

    /// The first address as the app will contact it: host (ASCII, lower case; an IPv6 address in brackets) and a
    /// port other than 443. Never a decoded Unicode form, so a look-alike name cannot pass for another.
    public var displayAddress: String {
        guard
            let url = urls.first,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let host = components.encodedHost
        else {
            return ""
        }
        let port = components.port.flatMap { $0 == 443 ? nil : ":\($0)" } ?? ""
        return host.lowercased() + port
    }

    /// A form-encoded value ("+" is a space); a malformed escape is refused.
    private static func formDecoded(_ raw: String) throws(ServerLinkError) -> String {
        guard let value = raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding else {
            throw .invalid
        }
        return value
    }

    private static func isSpaceOrControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace || scalar.properties.generalCategory == .control
    }
}
