import Foundation

public enum PairingError: Error, Equatable {
    /// No URL in the QR code could be reached.
    case noServerReachable
    /// At least one URL answered, but none could be verified as the server from the QR code.
    case serverNotVerified
    case invalidCode
    case tooManyAttempts
    /// A Brievie server that speaks another major API version, or answered pairing with unusable data.
    case incompatibleServer
    /// The task was cancelled; nothing was stored.
    case cancelled
    /// Anything else. The associated value is diagnostic only (logs, bug reports) and never shown to the user.
    case failed(String)
}

/// Pairs this device with the server described by a scanned QR code.
public struct PairingService: Sendable {
    private let server: any BrievieServer
    private let store: ConnectionStore

    public init(server: any BrievieServer, store: ConnectionStore) {
        self.server = server
        self.store = store
    }

    /// Tries the payload's URLs in order until one is verified as the server from the QR code, then redeems
    /// the code there and stores the pairing.
    ///
    /// - A URL that is unreachable, or that answers but cannot be verified (wrong CA, not a Brievie answer,
    ///   untrusted TLS), is skipped: nothing from it is used and the code is never sent to it.
    /// - A verified server with another major API version stops pairing (every URL is the same server).
    /// - Once the code has been sent, any failure stops pairing: the code is never sent to a second URL.
    /// - Nothing is stored unless pairing succeeds.
    public func pair(_ payload: PairingPayload, deviceName: String) async throws(PairingError) -> ServerConnection {
        var sawUnverifiableAnswer = false
        for url in payload.urls {
            if Task.isCancelled { throw .cancelled }
            switch await verify(url, caSHA256: payload.caSHA256) {
            case let .verified(attempt):
                return try await finish(attempt, url: url, payload: payload, deviceName: deviceName)
            case .unreachable:
                continue
            case .unverifiable:
                sawUnverifiableAnswer = true
            case .incompatible:
                throw .incompatibleServer
            case .cancelled:
                throw .cancelled
            }
        }
        throw sawUnverifiableAnswer ? .serverNotVerified : .noServerReachable
    }

    private struct Attempt {
        let caCertificateDER: Data?
        let trust: ServerTrust
    }

    private enum Verification {
        case verified(Attempt)
        case unreachable
        /// Something answered, but it is not verifiably the server from the QR code.
        case unverifiable
        /// The verified server speaks another major API version.
        case incompatible
        case cancelled
    }

    /// Steps 1–3: check the CA against the QR fingerprint, build the trust, check the API version.
    private func verify(_ url: URL, caSHA256: String?) async -> Verification {
        var caCertificateDER: Data?
        if let caSHA256 {
            let pem: String
            switch await call({ try await server.caCertificatePEM(at: url) }) {
            case let .success(value): pem = value
            case let .failure(error): return Self.verification(after: error)
            }
            // The PEM came over a connection nobody vouched for: it is only usable if it matches the QR code.
            guard
                let der = try? CertificatePin.der(fromPEM: pem),
                CertificatePin.sha256Hex(ofDER: der) == caSHA256
            else {
                return .unverifiable
            }
            caCertificateDER = der
        }
        let trust = ServerTrust(caCertificateDER: caCertificateDER)
        switch await call({ try await server.health(at: url, trust: trust) }) {
        case let .success(apiVersion):
            guard Self.isSupported(apiVersion: apiVersion) else { return .incompatible }
            return .verified(Attempt(caCertificateDER: caCertificateDER, trust: trust))
        case let .failure(error):
            return Self.verification(after: error)
        }
    }

    private static func verification(after error: CallError) -> Verification {
        switch error {
        case .cancelled: .cancelled
        case .server(.unreachable): .unreachable
        case .server: .unverifiable
        }
    }

    /// Steps 4–5: redeem the code and store the pairing. The code may already be spent once the request
    /// went out, so failures here never move on to the next URL.
    private func finish(
        _ attempt: Attempt, url: URL, payload: PairingPayload, deviceName: String
    ) async throws(PairingError) -> ServerConnection {
        if Task.isCancelled { throw .cancelled }
        let device: PairedDevice
        switch await call({
            try await server.pair(at: url, trust: attempt.trust, code: payload.code, deviceName: deviceName)
        }) {
        case let .success(value): device = value
        case .failure(.cancelled): throw .cancelled
        case let .failure(.server(error)): throw PairingError(error)
        }
        guard !device.token.isEmpty else { throw .incompatibleServer }
        // The code is spent; finish storing even if the task was cancelled meanwhile, so the device the
        // server now knows about is not lost.
        let connection = ServerConnection(
            urls: payload.urls,
            caCertificateDER: attempt.caCertificateDER,
            deviceID: device.deviceID,
            userName: device.userName
        )
        do {
            try store.save(connection, token: device.token)
        } catch {
            try? store.clear()
            throw .failed("storage: \(type(of: error))")
        }
        return connection
    }

    private enum CallError: Error {
        case cancelled
        case server(ServerError)
    }

    /// Runs a server call; cancellation (a `CancellationError` or a cancelled task) is told apart from the
    /// server's answer, because URLSession reports a cancelled task like a refused TLS challenge.
    private func call<T>(_ operation: () async throws -> T) async -> Result<T, CallError> {
        do {
            return .success(try await operation())
        } catch {
            if Task.isCancelled || error is CancellationError { return .failure(.cancelled) }
            if let error = error as? ServerError { return .failure(.server(error)) }
            return .failure(.server(.other(String(describing: type(of: error)))))
        }
    }

    /// This app speaks API version 1.x.
    private static func isSupported(apiVersion: String) -> Bool {
        apiVersion.split(separator: ".", omittingEmptySubsequences: false).first == "1"
    }
}

extension PairingError {
    init(_ error: ServerError) {
        switch error {
        case .unreachable: self = .noServerReachable
        case .untrusted: self = .serverNotVerified
        case .invalidCode: self = .invalidCode
        case .tooManyAttempts: self = .tooManyAttempts
        case .incompatible: self = .incompatibleServer
        case .unauthorized: self = .failed("unauthorized")
        case .other(let reason): self = .failed(reason)
        }
    }
}
