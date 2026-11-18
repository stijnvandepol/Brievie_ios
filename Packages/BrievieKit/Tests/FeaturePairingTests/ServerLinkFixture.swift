import BrievieCore
@testable import FeaturePairing
import Foundation
import Testing

/// A link model with a stub server and an in-memory store, for the `ServerLinkModel` suites.
@MainActor
final class ServerLinkFixture {
    static let pairingID = "0b7e2f4c-5d1a-4e8b-9c3f-6a2d8e1f4b70"
    static let pin = String(repeating: "ab", count: 32)
    static let publicLink = "brievie://server#v=1&url=https%3A%2F%2Fbrievie.example.nl&pairing=\(pairingID)"
    static let pinnedLink =
        "brievie://server#v=1&url=https%3A%2F%2Fbrievie.local&ca_sha256=\(pin)&pairing=\(pairingID)"
    static let otherLink = "brievie://server#v=1&url=https%3A%2F%2Fother.example.nl&pairing=\(pairingID)"
    static let qrPayload = #"{"v":1,"urls":["https://brievie.example.nl"],"code":"ABCD-EFGH","ca_sha256":null}"#

    let server = StubServer()
    let secrets = InMemorySecretStore()
    let paired = Paired()

    @MainActor
    final class Paired {
        var connections: [ServerConnection] = []
    }

    var unpaired: AppModel.State { .unpaired(notice: nil) }

    func ready() -> AppModel.State {
        .ready(ServerConnection(urls: [], caCertificateDER: nil, deviceID: UUID(), userName: "x"))
    }

    func makeModel(deviceName: String = "Stijns iPhone") -> ServerLinkModel {
        let paired = paired
        return ServerLinkModel(
            service: PairingService(server: server, store: ConnectionStore(secrets: secrets)),
            deviceName: { deviceName },
            onPaired: { paired.connections.append($0) }
        )
    }

    func url(_ text: String) throws -> URL {
        try #require(URL(string: text))
    }

    /// A link naming `hosts` in order, without a pin.
    func link(_ hosts: [String]) throws -> URL {
        let urls = hosts.map { "url=https%3A%2F%2F\($0)" }.joined(separator: "&")
        return try url("brievie://server#v=1&\(urls)&pairing=\(Self.pairingID)")
    }

    /// Receives `link` while unpaired, taps "Server zoeken" and waits until the server search ended.
    func receive(_ link: URL, on model: ServerLinkModel) async {
        model.receive(link, appState: unpaired)
        model.findServer()
        await model.searchTask?.value
    }

    /// A model showing the offer for the public-certificate link, with `code` typed.
    func offered(code: String = "abcd 2345") async throws -> ServerLinkModel {
        let model = makeModel()
        await receive(try url(Self.publicLink), on: model)
        model.code = code
        return model
    }

    func submitAndWait(_ model: ServerLinkModel) async {
        model.submit()
        await model.pairingTask?.value
    }

    func expectNothingStored(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(secrets.read(.deviceToken) == nil, sourceLocation: sourceLocation)
        #expect(secrets.read(.serverConnection) == nil, sourceLocation: sourceLocation)
    }
}
