@testable import BrievieCore
import Foundation
import Security
import Testing

@Suite struct ServerTrustTests {
    private func der(_ name: String) throws -> Data {
        try Fixtures.der(name)
    }

    private func serverTrust(leaf name: String) throws -> SecTrust {
        try Fixtures.serverTrust(leaf: name)
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
    private func delegate() throws -> PinnedSessionDelegate {
        PinnedSessionDelegate(trust: ServerTrust(caCertificateDER: try Fixtures.der("ca.pem")))
    }

    @Test func trustedServerGetsCredential() throws {
        let disposition = try delegate().disposition(
            authenticationMethod: NSURLAuthenticationMethodServerTrust,
            serverTrust: try Fixtures.serverTrust(leaf: "leaf-a.pem"),
            host: "localhost"
        )

        #expect(disposition == .useCredential)
    }

    @Test func serverForAnotherHostIsCancelled() throws {
        let disposition = try delegate().disposition(
            authenticationMethod: NSURLAuthenticationMethodServerTrust,
            serverTrust: try Fixtures.serverTrust(leaf: "leaf-a.pem"),
            host: "example.com"
        )

        #expect(disposition == .cancelAuthenticationChallenge)
    }

    @Test func serverFromAnotherCAIsCancelled() throws {
        let disposition = try delegate().disposition(
            authenticationMethod: NSURLAuthenticationMethodServerTrust,
            serverTrust: try Fixtures.serverTrust(leaf: "other-leaf.pem"),
            host: "localhost"
        )

        #expect(disposition == .cancelAuthenticationChallenge)
    }

    @Test func serverTrustChallengeWithoutTrustIsCancelled() throws {
        let disposition = try delegate().disposition(
            authenticationMethod: NSURLAuthenticationMethodServerTrust, serverTrust: nil, host: "localhost"
        )

        #expect(disposition == .cancelAuthenticationChallenge)
    }

    @Test(arguments: [NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodClientCertificate])
    func otherChallengesGetDefaultHandling(method: String) throws {
        let disposition = try delegate().disposition(
            authenticationMethod: method,
            serverTrust: try Fixtures.serverTrust(leaf: "other-leaf.pem"),
            host: "localhost"
        )

        #expect(disposition == .performDefaultHandling)
    }
}
