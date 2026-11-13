import BrievieCore
import Foundation
import Testing

/// Against a running Brievie server with a private CA (the host's Compose stack). Opt-in:
/// `BRIEVIE_LIVE_SERVER=https://localhost make test`.
@Suite(.enabled(
    if: ProcessInfo.processInfo.environment["BRIEVIE_LIVE_SERVER"] != nil,
    "Set BRIEVIE_LIVE_SERVER=https://localhost to run against a running Brievie server"
))
struct LiveServerIntegrationTests {
    private func serverURL() throws -> URL {
        let value = ProcessInfo.processInfo.environment["BRIEVIE_LIVE_SERVER"] ?? ""
        return try #require(URL(string: value), "BRIEVIE_LIVE_SERVER is not a URL: \(value)")
    }

    @Test func trustsOnlyTheServersOwnCA() async throws {
        let url = try serverURL()
        let server = LiveBrievieServer()

        let pem = try await server.caCertificatePEM(at: url)
        let der = try CertificatePin.der(fromPEM: pem)
        print("Live server CA SHA-256: \(CertificatePin.sha256Hex(ofDER: der))")

        let version = try await server.health(at: url, trust: ServerTrust(caCertificateDER: der))
        print("Live server api_version via pinned trust: \(version)")
        #expect(version.hasPrefix("1."))

        let fixtureTrust = ServerTrust(caCertificateDER: try Fixtures.der("ca.pem"))
        await #expect(throws: ServerError.untrusted) {
            try await server.health(at: url, trust: fixtureTrust)
        }
    }
}
