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
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            return (.performDefaultHandling, nil)
        }
        guard let serverTrust = space.serverTrust, trust.evaluate(serverTrust, host: space.host) else {
            return (.cancelAuthenticationChallenge, nil)
        }
        return (.useCredential, URLCredential(trust: serverTrust))
    }
}
