import BrievieAPI
import Foundation

/// `BrievieServer` over HTTPS, using the client generated from the host's `openapi.json`.
///
/// Every call runs on its own short-lived session whose delegate is a `PinnedSessionDelegate` for the given
/// trust; the session is invalidated when the call returns. Generated types never leave this file.
public struct LiveBrievieServer: BrievieServer {
    /// The largest JSON answer the app reads. The largest real one is a letter of 30 pages of 20000 characters
    /// each, a few megabytes even with every character escaped.
    public static let maxJSONResponseBytes = 16 * 1024 * 1024

    private let makeConfiguration: @Sendable () -> URLSessionConfiguration
    private let maxJSONBytes: Int
    private let appVersion: String?

    /// - Parameter appVersion: sent with every request (`AppVersionHeader`) and in the pairing body; `nil` sends
    ///   none.
    public init(appVersion: String? = AppVersionHeader.current()) {
        self.init(configuration: { .ephemeral }, appVersion: appVersion)
    }

    /// - Parameters:
    ///   - configuration: the base session configuration (tests route it to a stub); it is always hardened with
    ///     `SessionConfiguration.hardened`.
    ///   - maxJSONBytes: a longer JSON answer fails with `ServerError.responseTooLarge`.
    ///   - appVersion: as in the public initialiser; tests send none unless they ask.
    init(
        configuration: @escaping @Sendable () -> URLSessionConfiguration,
        maxJSONBytes: Int = LiveBrievieServer.maxJSONResponseBytes,
        appVersion: String? = nil
    ) {
        makeConfiguration = configuration
        self.maxJSONBytes = maxJSONBytes
        self.appVersion = appVersion
    }

    public func health(at url: URL, trust: ServerTrust) async throws -> String {
        try await withClient(url, trust: trust, token: nil) { client in
            switch try await client.getHealth() {
            case let .ok(response):
                return try response.body.json.apiVersion
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func caCertificatePEM(at url: URL) async throws -> String {
        // The only request made before any trust exists. It runs on a one-off session that accepts whatever
        // certificate the server presents, for this single GET only (see `CACertificateDownload`). The PEM it
        // returns is worthless until `PairingService` has checked its SHA-256 against the QR code.
        try await CACertificateDownload.pem(at: url, configuration: makeConfiguration())
    }

    public func pair(at url: URL, trust: ServerTrust, code: String, deviceName: String) async throws -> PairedDevice {
        try await withClient(url, trust: trust, token: nil) { client in
            switch try await client.pairDevice(
                body: .json(.init(appVersion: appVersion, code: code, deviceName: deviceName))
            ) {
            case let .created(response):
                let paired = try response.body.json
                guard let deviceID = UUID(uuidString: paired.deviceId) else { throw ServerError.incompatible }
                return PairedDevice(deviceID: deviceID, token: paired.token, userName: paired.user.name)
            case let .badRequest(response):
                throw ServerError(status: 400, code: try? response.body.json.code)
            case .contentTooLarge:
                throw ServerError(status: 413, code: nil)
            case .unsupportedMediaType:
                throw ServerError(status: 415, code: nil)
            case let .unprocessableContent(response):
                throw ServerError(status: 422, code: try? response.body.json.code)
            case .tooManyRequests:
                throw ServerError.tooManyAttempts
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func workspaces(at url: URL, trust: ServerTrust, token: String) async throws -> [WorkspaceSummary] {
        try await withClient(url, trust: trust, token: token) { client in
            switch try await client.listWorkspaces() {
            case let .ok(response):
                return try response.body.json.map(WorkspaceSummary.init(workspace:))
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func revokeDevice(_ deviceID: UUID, at url: URL, trust: ServerTrust, token: String) async throws {
        try await withClient(url, trust: trust, token: token) { client in
            switch try await client.revokeDevice(path: .init(deviceId: deviceID.uuidString.lowercased())) {
            case .noContent:
                return
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
            case let .forbidden(response):
                throw ServerError(status: 403, code: try? response.body.json.code)
            case let .notFound(response):
                throw ServerError(status: 404, code: try? response.body.json.code)
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    /// Runs `operation` on a client whose session only trusts what `trust` accepts and follows no redirects,
    /// then invalidates the session. Errors come out as `ServerError`, or `CancellationError` when the task
    /// was cancelled.
    func withClient<Result>(
        _ url: URL,
        trust: ServerTrust,
        token: String?,
        _ operation: (Client) async throws -> Result
    ) async throws -> Result {
        let session = URLSession(
            configuration: SessionConfiguration.hardened(makeConfiguration()),
            delegate: PinnedSessionDelegate(trust: trust),
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }
        do {
            return try await operation(
                APIClient.make(
                    baseURL: url, session: session, token: token, maxJSONBytes: maxJSONBytes, appVersion: appVersion
                )
            )
        } catch {
            throw ServerError.throwingCancellation(error)
        }
    }
}

private extension WorkspaceSummary {
    init(workspace: Components.Schemas.WorkspaceOut) throws(ServerError) {
        guard let id = UUID(uuidString: workspace.id) else { throw .incompatible }
        self.init(
            id: id,
            name: workspace.name,
            kind: Kind(rawValue: workspace.kind) ?? .unknown,
            role: Role(rawValue: workspace.role) ?? .unknown
        )
    }
}
