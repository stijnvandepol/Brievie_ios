import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// Builds the client generated from `openapi.json` (the host's contract, copied by `make sync-api`).
public enum APIClient {
    /// A client for the server at `baseURL` that sends its requests through `session`.
    ///
    /// The contract's paths already start with `/api/v1`, so `baseURL` is the server address from the
    /// pairing QR code. The caller owns `session`: it carries the trust decision (its delegate) and must be
    /// invalidated by the caller when the work is done.
    /// - Parameter token: the device token; when given, every request carries `Authorization: Bearer <token>`.
    public static func make(baseURL: URL, session: URLSession, token: String?) -> Client {
        Client(
            serverURL: baseURL,
            transport: URLSessionTransport(configuration: .init(session: session)),
            middlewares: token.map { [BearerTokenMiddleware(token: $0)] } ?? []
        )
    }
}

/// Adds `Authorization: Bearer <token>` to every request.
struct BearerTokenMiddleware: ClientMiddleware {
    let token: String

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[.authorization] = "Bearer \(token)"
        return try await next(request, body, baseURL)
    }
}
