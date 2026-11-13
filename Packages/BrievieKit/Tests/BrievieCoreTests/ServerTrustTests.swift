@testable import BrievieCore
import Foundation
import Security
import Testing

@Suite struct ServerTrustTests {
    private func der(_ name: String) throws -> Data {
        try CertificatePin.der(fromPEM: Fixtures.text(name))
    }

    /// A trust object for `leaf`, as a server would present it (leaf only, no chain), evaluated one day
    /// after the fixtures were issued so the tests do not expire with the 800-day leaves.
    private func serverTrust(leaf name: String) throws -> SecTrust {
        let certificate = try #require(SecCertificateCreateWithData(nil, try der(name) as CFData))
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust)
        #expect(status == errSecSuccess)
        let serverTrust = try #require(trust)
        #expect(SecTrustSetVerifyDate(serverTrust, try Fixtures.evaluationDate() as CFDate) == errSecSuccess)
        return serverTrust
    }

    @Test(arguments: ["leaf-a.pem", "leaf-b.pem"])
    func acceptsLeavesSignedByPinnedCA(leaf: String) throws {
        let trust = ServerTrust(caCertificateDER: try der("ca.pem"))

        #expect(trust.evaluate(try serverTrust(leaf: leaf), host: "localhost"))
    }

    @Test func refusesLeafFromAnotherCA() throws {
        let trust = ServerTrust(caCertificateDER: try der("ca.pem"))

        #expect(!trust.evaluate(try serverTrust(leaf: "other-leaf.pem"), host: "localhost"))
    }

    @Test func refusesLeafForAnotherHost() throws {
        let trust = ServerTrust(caCertificateDER: try der("ca.pem"))

        #expect(!trust.evaluate(try serverTrust(leaf: "leaf-a.pem"), host: "example.com"))
    }

    @Test func refusesTheCAItselfAsServerCertificate() throws {
        let trust = ServerTrust(caCertificateDER: try der("ca.pem"))

        #expect(!trust.evaluate(try serverTrust(leaf: "ca.pem"), host: "localhost"))
    }

    @Test func systemTrustRefusesPrivatelySignedLeaf() throws {
        let trust = ServerTrust(caCertificateDER: nil)

        #expect(!trust.evaluate(try serverTrust(leaf: "leaf-a.pem"), host: "localhost"))
    }

    @Test func malformedPinnedCARefusesEverything() throws {
        let trust = ServerTrust(caCertificateDER: Data("garbage".utf8))

        #expect(!trust.evaluate(try serverTrust(leaf: "leaf-a.pem"), host: "localhost"))
    }
}

@Suite struct PinnedSessionDelegateTests {
    private final class Sender: NSObject, URLAuthenticationChallengeSender {
        func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
        func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
        func cancel(_ challenge: URLAuthenticationChallenge) {}
    }

    private func challenge(method: String) -> URLAuthenticationChallenge {
        let space = URLProtectionSpace(
            host: "localhost", port: 443, protocol: "https", realm: nil, authenticationMethod: method
        )
        return URLAuthenticationChallenge(
            protectionSpace: space, proposedCredential: nil, previousFailureCount: 0,
            failureResponse: nil, error: nil, sender: Sender()
        )
    }

    @Test func otherChallengesGetDefaultHandling() async {
        let delegate = PinnedSessionDelegate(trust: ServerTrust(caCertificateDER: nil))

        let (disposition, credential) = await delegate.urlSession(
            URLSession.shared, didReceive: challenge(method: NSURLAuthenticationMethodHTTPBasic)
        )

        #expect(disposition == .performDefaultHandling)
        #expect(credential == nil)
    }

    @Test func serverTrustChallengeWithoutTrustIsCancelled() async {
        let delegate = PinnedSessionDelegate(trust: ServerTrust(caCertificateDER: nil))

        let (disposition, credential) = await delegate.urlSession(
            URLSession.shared, didReceive: challenge(method: NSURLAuthenticationMethodServerTrust)
        )

        #expect(disposition == .cancelAuthenticationChallenge)
        #expect(credential == nil)
    }
}
