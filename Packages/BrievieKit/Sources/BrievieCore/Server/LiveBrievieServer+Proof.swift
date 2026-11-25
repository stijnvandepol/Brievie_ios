import BrievieAPI
import Foundation

/// Pairing by proof (`createPairingChallenge`, `pairDeviceWithProof`). Generated types stay in this file.
extension LiveBrievieServer {
    public func pairingChallenge(at url: URL, trust: ServerTrust) async throws -> String {
        try await withClient(url, trust: trust, token: nil) { client in
            switch try await client.createPairingChallenge() {
            case let .created(response):
                let nonce = try response.body.json.nonce
                // Exactly the host's 43 base64url characters: see `PairingProof.isNonce`.
                guard PairingProof.isNonce(nonce) else { throw ServerError.incompatible }
                return nonce
            case .tooManyRequests:
                throw ServerError.tooManyAttempts
            case let .undocumented(status, payload):
                // The host's 403 `pair_at_home` on its public route is not in the contract: read its code.
                throw await LiveBrievieServer.undocumentedError(status: status, payload: payload)
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
            case let .undocumented(status, payload):
                // The host's 403 `pair_at_home` on its public route is not in the contract: read its code.
                throw await LiveBrievieServer.undocumentedError(status: status, payload: payload)
            }
        }
    }
}

extension PairedDevice {
    init(pairOut: Components.Schemas.PairOut) throws(ServerError) {
        guard let deviceID = UUID(uuidString: pairOut.deviceId) else { throw .incompatible }
        self.init(
            deviceID: deviceID, token: pairOut.token, userName: pairOut.user.name,
            publicURLs: (pairOut.publicUrls ?? []).compactMap(PairingPayload.httpsURL(from:))
        )
    }
}
