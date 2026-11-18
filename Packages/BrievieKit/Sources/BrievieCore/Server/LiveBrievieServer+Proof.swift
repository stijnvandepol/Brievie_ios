import BrievieAPI
import Foundation

/// Pairing by proof (`createPairingChallenge`, `pairDeviceWithProof`). Generated types stay in this file.
extension LiveBrievieServer {
    /// The host's nonces are `secrets.token_urlsafe(32)` (43 characters); the contract caps them at 64.
    static let maximumNonceLength = 64

    public func pairingChallenge(at url: URL, trust: ServerTrust) async throws -> String {
        try await withClient(url, trust: trust, token: nil) { client in
            switch try await client.createPairingChallenge() {
            case let .created(response):
                let nonce = try response.body.json.nonce
                guard Self.isNonce(nonce) else { throw ServerError.incompatible }
                return nonce
            case .tooManyRequests:
                throw ServerError.tooManyAttempts
            case let .undocumented(status, _):
                throw ServerError(status: status, code: nil)
            }
        }
    }

    public func pairWithProof(
        at url: URL, trust: ServerTrust, proof: CodeProof, deviceName: String
    ) async throws -> PairedDevice {
        let body = Components.Schemas.PairProofIn(
            appVersion: appVersion,
            deviceName: deviceName,
            nonce: proof.nonce,
            pairingId: proof.pairingID.uuidString.lowercased(),
            proof: proof.proof
        )
        return try await withClient(url, trust: trust, token: nil) { client in
            switch try await client.pairDeviceWithProof(body: .json(body)) {
            case let .created(response):
                return try PairedDevice(pairOut: try response.body.json)
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

    /// 1 to 64 characters of the URL-safe base64 alphabet.
    static func isNonce(_ nonce: String) -> Bool {
        (1...maximumNonceLength).contains(nonce.utf8.count) && nonce.utf8.allSatisfy { byte in
            PairingPayload.isASCIIAlphanumeric(byte) || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "_")
        }
    }
}

extension PairedDevice {
    init(pairOut: Components.Schemas.PairOut) throws(ServerError) {
        guard let deviceID = UUID(uuidString: pairOut.deviceId) else { throw .incompatible }
        self.init(deviceID: deviceID, token: pairOut.token, userName: pairOut.user.name)
    }
}
