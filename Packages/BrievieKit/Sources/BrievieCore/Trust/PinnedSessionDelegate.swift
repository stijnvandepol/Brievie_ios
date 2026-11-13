import Foundation

/// `URLSession` delegate that only lets TLS connections through when `ServerTrust` accepts the server.
public final class PinnedSessionDelegate: NSObject, URLSessionDelegate, Sendable {
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
