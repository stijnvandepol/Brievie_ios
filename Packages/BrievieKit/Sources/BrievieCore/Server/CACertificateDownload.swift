import BrievieAPI
import Foundation

/// The one request the app makes without trusting the server: `GET /api/v1/server/ca-certificate`.
///
/// Why accepting the server's certificate here is safe:
/// - The answer is worthless on its own. `PairingService` only uses the PEM after its SHA-256 matches the
///   fingerprint in the QR code, which came from the server's web interface, not from this connection.
///   A man in the middle can make the fetch fail, but cannot make the app trust his certificate.
/// - Nothing secret goes out: no device token, no cookies, no stored credentials, no inherited headers.
///
/// How it is contained:
/// - The session and its delegate are created inside `pem(at:configuration:)`, used for exactly one GET to a
///   fixed path on the given host, and invalidated before the function returns. Neither escapes.
/// - The delegate accepts a server-trust challenge only for that host and cancels every other challenge.
/// - Redirects are never followed, and the response is capped at `maximumBytes` (a CA certificate is a few kB).
enum CACertificateDownload {
    static let maximumBytes = 64 * 1024
    private static let path = "api/v1/server/ca-certificate"

    /// Errors are `ServerError`, or `CancellationError` when the task was cancelled.
    static func pem(
        at baseURL: URL, configuration: URLSessionConfiguration, acceptLanguage: String? = nil
    ) async throws -> String {
        guard let host = baseURL.host(), baseURL.scheme?.lowercased() == "https" else {
            throw ServerError.other("invalid_url")
        }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let acceptLanguage { request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language") }

        let session = URLSession(
            configuration: SessionConfiguration.hardened(configuration),
            delegate: Delegate(host: host),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        let status: Int
        let body: Data
        do {
            (status, body) = try await fetch(request, on: session)
        } catch {
            throw ServerError.throwingCancellation(error)
        }

        guard status == 200 else {
            let code = try? JSONDecoder().decode(Components.Schemas.ErrorOut.self, from: body).code
            throw ServerError(status: status, code: code)
        }
        guard let certificate = try? JSONDecoder().decode(Components.Schemas.CaCertificateOut.self, from: body) else {
            throw ServerError.incompatible
        }
        return certificate.pem
    }

    /// The status and at most `maximumBytes` of body; a longer body throws `response_too_large`.
    private static func fetch(_ request: URLRequest, on session: URLSession) async throws -> (Int, Data) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw ServerError.incompatible }
        guard response.expectedContentLength <= maximumBytes else { throw ServerError.responseTooLarge }
        var body = Data()
        for try await byte in bytes {
            guard body.count < maximumBytes else { throw ServerError.responseTooLarge }
            body.append(byte)
        }
        return (response.statusCode, body)
    }

    /// Server trust for the requested host is accepted without evaluation; every other challenge is cancelled.
    static func disposition(
        authenticationMethod: String,
        serverTrust: SecTrust?,
        challengeHost: String,
        requestedHost: String
    ) -> URLSession.AuthChallengeDisposition {
        guard
            authenticationMethod == NSURLAuthenticationMethodServerTrust,
            serverTrust != nil,
            challengeHost.caseInsensitiveCompare(requestedHost) == .orderedSame
        else {
            return .cancelAuthenticationChallenge
        }
        return .useCredential
    }

    /// Accepts the server's certificate for `host` only; sends no credentials and follows no redirects.
    /// Private: only `pem(at:configuration:)` can create one.
    private final class Delegate: NSObject, URLSessionTaskDelegate, Sendable {
        private let host: String

        init(host: String) {
            self.host = host
        }

        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge
        ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            answer(challenge)
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge
        ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            answer(challenge)
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            nil
        }

        private func answer(
            _ challenge: URLAuthenticationChallenge
        ) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            let space = challenge.protectionSpace
            let decision = CACertificateDownload.disposition(
                authenticationMethod: space.authenticationMethod,
                serverTrust: space.serverTrust,
                challengeHost: space.host,
                requestedHost: host
            )
            guard decision == .useCredential, let serverTrust = space.serverTrust else {
                return (decision, nil)
            }
            return (.useCredential, URLCredential(trust: serverTrust))
        }
    }
}
