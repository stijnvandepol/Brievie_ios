import Foundation

public enum PairingError: Error, Equatable {
    case noServerReachable
    case serverNotVerified
    case invalidCode
    case tooManyAttempts
    case incompatibleServer
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

    /// Tries the payload's URLs in order. Only an unreachable URL moves on to the next one: a server that
    /// cannot be verified, or any refusal, stops pairing. Nothing is stored unless pairing succeeds.
    public func pair(_ payload: PairingPayload, deviceName: String) async throws(PairingError) -> ServerConnection {
        for url in payload.urls {
            let attempt: Attempt
            do {
                attempt = try await verify(url, caSHA256: payload.caSHA256)
            } catch .unreachable {
                continue
            } catch {
                throw PairingError(error)
            }
            return try await finish(attempt, url: url, payload: payload, deviceName: deviceName)
        }
        throw .noServerReachable
    }

    private struct Attempt {
        let caCertificateDER: Data?
        let trust: ServerTrust
    }

    /// Steps 1–3: check the CA against the QR fingerprint, build the trust, check the API version.
    private func verify(_ url: URL, caSHA256: String?) async throws(ServerError) -> Attempt {
        var caCertificateDER: Data?
        if let caSHA256 {
            let pem = try await call { try await server.caCertificatePEM(at: url) }
            // The PEM came over a connection nobody vouched for: it is only usable if it matches the QR code.
            guard
                let der = try? CertificatePin.der(fromPEM: pem),
                CertificatePin.sha256Hex(ofDER: der) == caSHA256
            else {
                throw .untrusted
            }
            caCertificateDER = der
        }
        let trust = ServerTrust(caCertificateDER: caCertificateDER)
        let apiVersion = try await call { try await server.health(at: url, trust: trust) }
        guard Self.isSupported(apiVersion: apiVersion) else { throw .incompatible }
        return Attempt(caCertificateDER: caCertificateDER, trust: trust)
    }

    /// Steps 4–5: redeem the code and store the pairing. The code may already be spent once the request
    /// went out, so failures here never move on to the next URL.
    private func finish(
        _ attempt: Attempt, url: URL, payload: PairingPayload, deviceName: String
    ) async throws(PairingError) -> ServerConnection {
        let device: PairedDevice
        do {
            device = try await call {
                try await server.pair(at: url, trust: attempt.trust, code: payload.code, deviceName: deviceName)
            }
        } catch {
            throw PairingError(error)
        }
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
            throw .failed("storage: \(error)")
        }
        return connection
    }

    private func call<T>(_ operation: () async throws -> T) async throws(ServerError) -> T {
        do {
            return try await operation()
        } catch let error as ServerError {
            throw error
        } catch {
            throw .other(String(describing: error))
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
