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
            configuration: Configuration(dateTranscoder: FlexibleDateTranscoder()),
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

/// Reads ISO 8601 timestamps with or without fractional seconds; the host sends both (a timestamp that
/// falls on a whole second has no fraction). Writes them without a fraction.
struct FlexibleDateTranscoder: DateTranscoder {
    func encode(_ date: Date) throws -> String {
        date.formatted(.iso8601)
    }

    func decode(_ dateString: String) throws -> Date {
        if let date = try? Date(dateString, strategy: .iso8601) {
            return date
        }
        if let date = try? Date(dateString, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        throw DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "Expected an ISO 8601 timestamp.")
        )
    }
}
