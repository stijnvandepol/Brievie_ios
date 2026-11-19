import Foundation

public enum PairingError: Error, Equatable {
    /// No URL in the QR code could be reached.
    case noServerReachable
    /// At least one URL answered, but none could be verified as the server from the QR code.
    case serverNotVerified
    case invalidCode
    case tooManyAttempts
    /// The connection dropped, or stopped being trusted, after the code may have been sent. The code can be
    /// spent: the user needs a new one (unlike `.noServerReachable`, where the code was never sent).
    case connectionLostWhilePairing
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
        // A cancel that landed during the last URL looks like "unreachable" or "untrusted" to the loop.
        if Task.isCancelled { throw .cancelled }
        throw sawUnverifiableAnswer ? .serverNotVerified : .noServerReachable
    }

    /// Pairs from a server link in one go: `locate(_:)`, then `pair(link:at:code:deviceName:)`. The link sheet calls
    /// the two steps itself, so the address it shows while the code is typed is the one the proof goes to.
    public func pair(
        link: ServerLink, code: PairingCode, deviceName: String
    ) async throws(PairingError) -> ServerConnection {
        try await pair(link: link, at: try await locate(link), code: code, deviceName: deviceName)
    }

    /// Finds the server a link names before any code exists: tries the link's URLs as `pair(_:deviceName:)` does
    /// (CA pin and health first; an unverifiable or unreachable URL is skipped) and fixes the first verified one.
    ///
    /// - The proof will be bound to what TLS validates for that connection: the pinned CA, or for a link without
    ///   a pin the host name. A URL whose name no public authority certifies is not contacted without a pin.
    /// - Nothing derived from the code exists yet, so nothing of it can go out; nothing is stored.
    public func locate(_ link: ServerLink) async throws(PairingError) -> LocatedServer {
        var sawUnverifiableAnswer = false
        for url in link.urls {
            if Task.isCancelled { throw .cancelled }
            if link.caSHA256 == nil, PairingProof.publicHostBinding(of: url) == nil {
                sawUnverifiableAnswer = true
                continue
            }
            switch await verify(url, caSHA256: link.caSHA256) {
            case let .verified(attempt):
                let binding = PairingProof.trustBinding(caCertificateDER: attempt.caCertificateDER, connectedTo: url)
                guard let binding else {
                    sawUnverifiableAnswer = true
                    continue
                }
                return LocatedServer(url: url, attempt: attempt, binding: binding)
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
        if Task.isCancelled { throw .cancelled }
        throw sawUnverifiableAnswer ? .serverNotVerified : .noServerReachable
    }

    /// Pairs at the server `locate(_:)` fixed: challenge, key, proof, store, all at `server.url` and nowhere else.
    ///
    /// - The code is never sent: only `PairingProof` reads it, and only the proof leaves this call.
    /// - A server without the proof path (404 on the challenge) is `.incompatibleServer`: never a fallback that
    ///   sends the code.
    /// - Any failure ends here, without another address. Nothing is stored unless pairing succeeds.
    public func pair(
        link: ServerLink, at located: LocatedServer, code: PairingCode, deviceName: String
    ) async throws(PairingError) -> ServerConnection {
        let url = located.url
        let attempt = located.attempt
        let nonce: String
        switch await call({ try await server.pairingChallenge(at: url, trust: attempt.trust) }) {
        case let .success(value): nonce = value
        case .failure(.cancelled): throw .cancelled
        case let .failure(.server(error)): throw PairingError(challenge: error)
        }
        let proof = try await Self.proof(
            code: code, pairingID: link.pairingID, nonce: nonce, binding: located.binding
        )
        let device: PairedDevice
        switch await call({
            try await server.pairWithProof(at: url, trust: attempt.trust, proof: proof, deviceName: deviceName)
        }) {
        case let .success(value): device = value
        case .failure(.cancelled): throw .cancelled
        case let .failure(.server(error)): throw PairingError(pairing: error)
        }
        return try store(device, urls: Self.storedURLs(link, located: located), attempt: attempt)
    }

    /// What a link pairing keeps. With a pinned CA every later connection to any address (API calls, uploads,
    /// unpairing) is anchored to that CA alone (`ServerTrust`), so the link's addresses stay, as on the QR path.
    /// Without one a later connection trusts the system roots: an extra address in someone else's link (own
    /// domain, valid public certificate) would get the device token, so only the proven address is kept.
    private static func storedURLs(_ link: ServerLink, located: LocatedServer) -> [URL] {
        located.attempt.caCertificateDER == nil ? [located.url] : link.urls
    }

    /// The proof for `nonce`; cancellation is checked before and after the slow key derivation. A nonce of
    /// another length or alphabet gets no proof (`PairingProof.isNonce`): nothing is derived or sent.
    private static func proof(
        code: PairingCode, pairingID: UUID, nonce: String, binding: String
    ) async throws(PairingError) -> CodeProof {
        if Task.isCancelled { throw .cancelled }
        guard PairingProof.isNonce(nonce) else { throw .incompatibleServer }
        let value = await PairingProof.proof(code: code, pairingID: pairingID, nonce: nonce, trustBinding: binding)
        guard let value else { throw .failed("key_derivation") }
        if Task.isCancelled { throw .cancelled }
        return CodeProof(pairingID: pairingID, nonce: nonce, proof: value)
    }

    fileprivate struct Attempt {
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
        case let .failure(.server(error)): throw PairingError(pairing: error)
        }
        return try store(device, urls: payload.urls, attempt: attempt)
    }

    /// Stores a pairing the server accepted. The code is spent; this finishes even if the task was cancelled
    /// meanwhile, so the device the server now knows about is not lost.
    private func store(_ device: PairedDevice, urls: [URL], attempt: Attempt) throws(PairingError) -> ServerConnection {
        guard !device.token.isEmpty else { throw .incompatibleServer }
        let connection = ServerConnection(
            urls: urls,
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

/// The server a link named, verified before any code exists: where the challenge and the proof will go.
public struct LocatedServer: Sendable {
    /// The one address pairing uses.
    public let url: URL
    fileprivate let attempt: PairingService.Attempt
    /// What the proof is bound to (`PairingProof.trustBinding`).
    let binding: String

    /// The address as the app contacts it: ASCII host (an IPv6 address in brackets) and a port other than 443.
    public var displayAddress: String {
        ServerLink.displayAddress(of: url)
    }
}

extension PairingError {
    /// The answer to the challenge request: nothing was sent yet, so a lost connection spent nothing.
    init(challenge error: ServerError) {
        switch error {
        case .unreachable, .untrusted: self = .noServerReachable
        // A 1c server has no proof path; the code is not sent there instead.
        case .other("http_404"), .incompatible: self = .incompatibleServer
        case .tooManyAttempts: self = .tooManyAttempts
        case .invalidCode, .unauthorized: self = .failed("challenge_refused")
        case .other(let reason): self = .failed(reason)
        }
    }

    /// The answer to the call that sends the code. Unlike the checks before it, a lost or untrusted connection
    /// here may have happened after the server accepted the code.
    init(pairing error: ServerError) {
        switch error {
        case .unreachable, .untrusted: self = .connectionLostWhilePairing
        case .invalidCode: self = .invalidCode
        case .tooManyAttempts: self = .tooManyAttempts
        case .incompatible: self = .incompatibleServer
        case .unauthorized: self = .failed("unauthorized")
        case .other(let reason): self = .failed(reason)
        }
    }
}
