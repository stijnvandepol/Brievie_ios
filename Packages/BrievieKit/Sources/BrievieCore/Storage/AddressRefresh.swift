import Foundation

/// Learning the server's addresses after pairing (external access, host PR #53, iOS I3): at most once a day, and
/// only over a CA-pinned connection, the app asks `getServerAddresses` and keeps what the server said. Pure: the
/// caller asks and stores.
public enum AddressRefresh {
    public static let interval: TimeInterval = 24 * 60 * 60

    /// Whether to ask `url` now: the pairing has a CA, `url` is not one of the public addresses (a connection
    /// there is not pinned; the server refuses it anyway), and the last answer is a day old or missing.
    public static func isDue(_ connection: ServerConnection, at url: URL, now: Date) -> Bool {
        guard connection.caCertificateDER != nil, !connection.isPublic(url) else { return false }
        guard let checked = connection.addressesCheckedAt else { return true }
        return now.timeIntervalSince(checked) >= interval || now < checked
    }

    /// The pairing with the server's addresses, or `nil` when the answer holds no usable address. Only https
    /// addresses are kept; a public address must be one of them.
    public static func updated(
        _ connection: ServerConnection, with answer: ServerAddresses, now: Date
    ) -> ServerConnection? {
        let urls = answer.urls.compactMap(PairingPayload.httpsURL(from:))
        guard !urls.isEmpty, connection.caCertificateDER != nil else { return nil }
        return ServerConnection(
            urls: urls, caCertificateDER: connection.caCertificateDER, deviceID: connection.deviceID,
            userName: connection.userName,
            publicURLs: answer.publicURLs.compactMap(PairingPayload.httpsURL(from:)), addressesCheckedAt: now
        )
    }

    /// Asks `url` for the addresses when due and stores what is usable. Only for the stored pairing of `deviceID`
    /// (unpaired meanwhile: nothing). A failure changes nothing; a server without the list (404) is asked again a
    /// day later.
    public static func refresh(
        store: ConnectionStore, server: any BrievieServer, deviceID: UUID, at url: URL, token: String
    ) async {
        let now = Date()
        guard
            let stored = try? store.load(), stored.connection.deviceID == deviceID,
            isDue(stored.connection, at: url, now: now)
        else { return }
        let updated: ServerConnection?
        do {
            // `url` is not public (`isDue`): the stored trust anchors it to the CA.
            let answer = try await server.serverAddresses(at: url, trust: stored.connection.trust, token: token)
            updated = Self.updated(stored.connection, with: answer, now: now)
        } catch ServerError.other("http_404") {
            updated = checked(stored.connection, now: now)
        } catch {
            return
        }
        guard let updated else { return }
        try? store.save(updated, token: stored.token)
    }

    /// The pairing unchanged, but asked `now`: a server without the list is not asked again for a day.
    public static func checked(_ connection: ServerConnection, now: Date) -> ServerConnection {
        ServerConnection(
            urls: connection.urls, caCertificateDER: connection.caCertificateDER, deviceID: connection.deviceID,
            userName: connection.userName, publicURLs: connection.publicURLs, addressesCheckedAt: now
        )
    }
}
