import BrievieAPI
import Foundation
import OpenAPIRuntime

/// External access (host PR #53): the server's addresses, and the 403 `pair_at_home` its public route gives
/// pairing and the address list. Generated types stay in this file.
extension LiveBrievieServer {
    public func serverAddresses(at url: URL, trust: ServerTrust, token: String) async throws -> ServerAddresses {
        try await withClient(url, trust: trust, token: token) { client in
            switch try await client.getServerAddresses() {
            case let .ok(response):
                let answer = try response.body.json
                return ServerAddresses(urls: answer.urls, publicURLs: answer.publicUrls)
            case let .unauthorized(response):
                throw ServerError(status: 401, code: try? response.body.json.code)
            case let .undocumented(status, payload):
                throw await Self.undocumentedError(status: status, payload: payload)
            }
        }
    }

    /// An answer the contract does not list. Only a 403's body is read (at most 16 KB), for the host's
    /// `pair_at_home`; every other status keeps the fixed form `http_<status>` as before (an undocumented 401 must
    /// never read as a revocation).
    static func undocumentedError(status: Int, payload: UndocumentedPayload) async -> ServerError {
        guard
            status == 403,
            let body = payload.body,
            let data = try? await Data(collecting: body, upTo: 16 * 1024),
            let error = try? JSONDecoder().decode(Components.Schemas.ErrorOut.self, from: data)
        else {
            return ServerError(status: status, code: nil)
        }
        return ServerError(status: status, code: error.code)
    }
}
