import Foundation

/// Everything the app needs to reach its paired server, apart from the device token.
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
