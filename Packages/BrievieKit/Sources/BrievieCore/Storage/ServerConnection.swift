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

    public init(urls: [URL], caCertificateDER: Data?, deviceID: UUID, userName: String) {
        self.urls = urls
        self.caCertificateDER = caCertificateDER
        self.deviceID = deviceID
        self.userName = userName
    }
}
