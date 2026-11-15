import Foundation

/// The calls the app makes to a Brievie server. Features talk to this seam, never to the generated API types.
public protocol BrievieServer: Sendable {
    /// The server's `api_version` (for example `"1.0.0"`).
    func health(at url: URL, trust: ServerTrust) async throws -> String
    /// The server's CA certificate as PEM, fetched before any trust exists. The result must not be trusted
    /// until its SHA-256 matches the fingerprint in the pairing QR code.
    func caCertificatePEM(at url: URL) async throws -> String
    /// Exchanges a one-time pairing code for a device token.
    func pair(at url: URL, trust: ServerTrust, code: String, deviceName: String) async throws -> PairedDevice
    /// The workspaces the paired user belongs to.
    func workspaces(at url: URL, trust: ServerTrust, token: String) async throws -> [WorkspaceSummary]
    /// Revokes the device `deviceID` on the server with its own token (unpairing). 401 and 404
    /// (`device_not_found`) mean the server no longer knows the device.
    func revokeDevice(_ deviceID: UUID, at url: URL, trust: ServerTrust, token: String) async throws
}

/// The result of a successful pairing.
public struct PairedDevice: Equatable, Sendable {
    public let deviceID: UUID
    public let token: String
    public let userName: String

    public init(deviceID: UUID, token: String, userName: String) {
        self.deviceID = deviceID
        self.token = token
        self.userName = userName
    }
}

public struct WorkspaceSummary: Equatable, Sendable, Identifiable {
    /// Raw values match the API. API v1 is additive: a value this app does not know yet is `.unknown`.
    public enum Kind: String, Sendable {
        case home
        case business
        case unknown
    }

    /// Raw values match the API. API v1 is additive: a value this app does not know yet is `.unknown`.
    public enum Role: String, Sendable {
        case admin
        case member
        case viewer
        case unknown
    }

    public let id: UUID
    public let name: String
    public let kind: Kind
    public let role: Role

    public init(id: UUID, name: String, kind: Kind, role: Role) {
        self.id = id
        self.name = name
        self.kind = kind
        self.role = role
    }
}

public enum ServerError: Error, Equatable {
    /// No connection could be made (no route, timeout, DNS failure, connection lost).
    case unreachable
    /// The TLS connection was refused because the server's certificate is not trusted.
    case untrusted
    /// HTTP 401: the device token is missing, wrong or revoked.
    case unauthorized
    /// The pairing code is unknown, expired or already used.
    case invalidCode
    /// HTTP 429.
    case tooManyAttempts
    /// The server answered with something this app does not understand.
    case incompatible
    /// Anything else. The associated value is diagnostic only and never shown to the user: an error code
    /// from a closed set known from the contract, or a fixed form such as `http_404` or `url_error_-1001`.
    case other(String)
}
