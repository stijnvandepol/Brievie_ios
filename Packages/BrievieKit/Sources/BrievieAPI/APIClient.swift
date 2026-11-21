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
    /// - Parameters:
    ///   - token: the device token; when given, every request carries `Authorization: Bearer <token>`.
    ///   - maxJSONBytes: the largest JSON answer read; a longer one throws `ResponseTooLargeError`.
    ///   - appVersion: when given, every request carries it in `AppVersionHeader.name`.
    ///   - acceptLanguage: the `Accept-Language` of every request, read when the request is made; the default is
    ///     the user's preferred languages (`AcceptLanguageHeader`).
    public static func make(
        baseURL: URL, session: URLSession, token: String?, maxJSONBytes: Int, appVersion: String? = nil,
        acceptLanguage: @escaping @Sendable () -> String? = { AcceptLanguageHeader.current() }
    ) -> Client {
        let cap = ResponseSizeMiddleware(maxJSONBytes: maxJSONBytes)
        return Client(
            serverURL: baseURL,
            configuration: Configuration(dateTranscoder: FlexibleDateTranscoder()),
            transport: URLSessionTransport(configuration: .init(session: session)),
            middlewares: [ForeignUnauthorizedMiddleware(), cap]
                + (token.map { [BearerTokenMiddleware(token: $0)] } ?? [])
                + (appVersion.map { [AppVersionMiddleware(value: $0)] } ?? [])
                + [AcceptLanguageMiddleware(value: acceptLanguage)]
        )
    }
}

/// A 401 that is not a JSON answer: not from the Brievie server (a reverse proxy's login page, say), so not its
/// verdict on the device token.
public struct ForeignUnauthorizedError: Error, Equatable {}

/// Stops a 401 without a JSON body before the generated client fails on its content type, so the caller can
/// tell it from the host's own `not_authenticated`.
struct ForeignUnauthorizedMiddleware: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (response, responseBody) = try await next(request, body, baseURL)
        let isJSON = response.headerFields[.contentType]?.lowercased().contains("json") ?? false
        if response.status.code == 401, !isJSON { throw ForeignUnauthorizedError() }
        return (response, responseBody)
    }
}

/// The server sent a JSON answer longer than the client reads.
public struct ResponseTooLargeError: Error, Equatable {
    public let maxBytes: Int
}

/// Reads every answer that is not a page image into memory, at most `maxJSONBytes`, before the generated client
/// decodes it: a broken or hostile server cannot make the app hold an unbounded body. Page images
/// (`getDocumentPage` answering with an image) are streamed and capped by their caller.
struct ResponseSizeMiddleware: ClientMiddleware {
    let maxJSONBytes: Int

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (response, responseBody) = try await next(request, body, baseURL)
        guard let responseBody else { return (response, nil) }
        let isImage = response.headerFields[.contentType]?.lowercased().hasPrefix("image/") ?? false
        if operationID == "getDocumentPage", isImage { return (response, responseBody) }
        if case .known(let length) = responseBody.length, length > maxJSONBytes {
            throw ResponseTooLargeError(maxBytes: maxJSONBytes)
        }
        var bytes: [UInt8] = []
        for try await chunk in responseBody {
            guard bytes.count + chunk.count <= maxJSONBytes else { throw ResponseTooLargeError(maxBytes: maxJSONBytes) }
            bytes.append(contentsOf: chunk)
        }
        return (response, HTTPBody(bytes))
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

/// Adds `X-Brievie-App-Version` to every request. A header name the HTTP types refuse sends the request without it.
struct AppVersionMiddleware: ClientMiddleware {
    let value: String

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if let name = HTTPField.Name(AppVersionHeader.name) {
            request.headerFields[name] = value
        }
        return try await next(request, body, baseURL)
    }
}

/// Adds `Accept-Language` to every request.
struct AcceptLanguageMiddleware: ClientMiddleware {
    let value: @Sendable () -> String?

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if let language = value() { request.headerFields[.acceptLanguage] = language }
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
