import Foundation

/// `URLSession` delegate that only lets TLS connections through when `ServerTrust` accepts the server,
/// and never follows a redirect: the API does not redirect, and a followed redirect could carry the
/// `Authorization` header or a request body (the pairing code) to another host.
public final class PinnedSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let trust: ServerTrust

    public init(trust: ServerTrust) {
        self.trust = trust
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        let decision = disposition(
            authenticationMethod: space.authenticationMethod, serverTrust: space.serverTrust, host: space.host
        )
        guard decision == .useCredential, let serverTrust = space.serverTrust else {
            return (decision, nil)
        }
        return (.useCredential, URLCredential(trust: serverTrust))
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }

    /// The answer to an authentication challenge: only server-trust challenges are decided here.
    func disposition(
        authenticationMethod: String,
        serverTrust: SecTrust?,
        host: String
    ) -> URLSession.AuthChallengeDisposition {
        guard authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            return .performDefaultHandling
        }
        guard let serverTrust, trust.evaluate(serverTrust, host: host) else {
            return .cancelAuthenticationChallenge
        }
        return .useCredential
    }
}
