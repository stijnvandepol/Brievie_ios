import Foundation

/// What a transport reports back about the uploads it runs.
public enum UploadEvent: Sendable {
    case sent(itemID: UUID, bytes: Int64, of: Int64)
    /// `deviceID` is the pairing the attempt was started with.
    case finished(itemID: UUID, deviceID: UUID, outcome: UploadOutcome)
    /// The system has delivered every event of a background relaunch.
    case allEventsDelivered
}

/// Sends queued upload bodies. The live one is a background `URLSession`, which keeps uploading while the
/// app is suspended or was ended by the system.
public protocol UploadTransport: Sendable {
    /// Buffered and created with the transport, so events of a relaunch are kept until somebody reads them.
    var events: AsyncStream<UploadEvent> { get }

    /// Starts a POST of the item's body file, or schedules it for `earliestBegin`.
    // swiftlint:disable:next function_parameter_count
    func start(
        itemID: UUID, deviceID: UUID, url: URL, bodyFile: URL, boundary: String, token: String, earliestBegin: Date?
    ) async

    /// The items whose upload is running or scheduled.
    func runningItemIDs() async -> Set<UUID>

    func cancel(itemID: UUID) async
}

/// The trust decision for uploads, read again for every TLS handshake: the background session lives
/// longer than a pairing.
public protocol UploadTrustProvider: Sendable {
    /// `nil` when nothing is paired or the Keychain cannot be read; the connection is then refused.
    func currentTrust() -> ServerTrust?
}

/// The pin of the stored pairing.
public struct StoredConnectionTrustProvider: UploadTrustProvider {
    private let store: ConnectionStore

    public init(store: ConnectionStore) {
        self.store = store
    }

    public func currentTrust() -> ServerTrust? {
        guard let stored = try? store.load() else { return nil }
        // A server with a public certificate has no pinned CA: system trust is then the right check.
        return ServerTrust(caCertificateDER: stored.connection.caCertificateDER)
    }
}
