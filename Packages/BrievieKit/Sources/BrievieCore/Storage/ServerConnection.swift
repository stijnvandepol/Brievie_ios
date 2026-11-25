import Foundation

/// Everything the app needs to reach its paired server, apart from the device token.
///
/// Stored as JSON in the Keychain. New stored properties must be optional (or decode with a default):
/// a value that no longer decodes makes `ConnectionStore.load()` clear the pairing, unpairing the user.
public struct ServerConnection: Codable, Equatable, Sendable {
    /// Server addresses in server order: the local address first.
    public let urls: [URL]
    /// The server's CA certificate; `nil` when the server uses a public certificate.
    public let caCertificateDER: Data?
    public let deviceID: UUID
    public let userName: String
    /// The entries of `urls` the server said carry a public certificate (a tunnel); `nil` in a pairing stored
    /// before external access, which still decodes. Only ever filled from what the server sent over a CA-pinned
    /// connection (QR, `PairOut.public_urls`, `getServerAddresses`), and only with https entries of `urls`.
    public let publicURLs: [URL]?
    /// When `getServerAddresses` last answered; `nil` before the first time.
    public let addressesCheckedAt: Date?

    public init(
        urls: [URL], caCertificateDER: Data?, deviceID: UUID, userName: String, publicURLs: [URL]? = nil,
        addressesCheckedAt: Date? = nil
    ) {
        self.urls = urls
        self.caCertificateDER = caCertificateDER
        self.deviceID = deviceID
        self.userName = userName
        // Without a CA there is no pinned connection the list could have come over, and system trust already
        // applies to every address: nothing to keep.
        let kept = caCertificateDER == nil ? [] : Self.publicEntries(publicURLs ?? [], of: urls)
        self.publicURLs = kept.isEmpty ? nil : kept
        self.addressesCheckedAt = addressesCheckedAt
    }

    /// The https entries of `candidates` that are also entries of `urls`; anything else is dropped.
    static func publicEntries(_ candidates: [URL], of urls: [URL]) -> [URL] {
        let known = Set(urls.map(\.absoluteString))
        var seen: Set<String> = []
        return candidates.filter { url in
            url.scheme?.lowercased() == "https" && url.host() != nil && known.contains(url.absoluteString)
                && seen.insert(url.absoluteString).inserted
        }
    }

    /// The trust for every call of this pairing: the CA for every address, except the server's public ones.
    public var trust: ServerTrust {
        ServerTrust(
            caCertificateDER: caCertificateDER,
            publicHosts: Set((publicURLs ?? []).compactMap { $0.host()?.lowercased() })
        )
    }

    /// Whether `url` is one of the server's public addresses (a connection there is not CA-pinned).
    public func isPublic(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return (publicURLs ?? []).contains { $0.host()?.lowercased() == host }
    }
}

extension ServerConnection {
    /// Which server this pairing belongs to, stable across pairing the same server again: the pinned CA
    /// when there is one, otherwise the set of addresses. A queued scan carries it, so a scan made for one
    /// server is never sent to another.
    public var serverID: String {
        if let caCertificateDER {
            return "ca:" + CertificatePin.sha256Hex(ofDER: caCertificateDER)
        }
        return "hosts:" + urls.map { $0.host()?.lowercased() ?? $0.absoluteString }.sorted().joined(separator: ",")
    }
}
