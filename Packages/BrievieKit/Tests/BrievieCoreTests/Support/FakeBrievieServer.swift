@testable import BrievieCore
import Foundation
import Synchronization
import Testing

/// A `BrievieServer` whose answers are set per test and which records every call.
final class FakeBrievieServer: BrievieServer {
    enum Call: Equatable {
        case caCertificate(URL)
        case health(URL)
        case pair(URL, code: String, name: String)
        case revoke(URL, deviceID: UUID, token: String)

        var isPair: Bool {
            if case .pair = self { true } else { false }
        }

        var isCACertificate: Bool {
            if case .caCertificate = self { true } else { false }
        }
    }

    static let device = PairedDevice(
        deviceID: UUID(uuidString: "F5400FDE-D094-49BA-9B51-62596E6DF070") ?? UUID(),
        token: "device-token-123",
        userName: "Beheerder"
    )

    private struct State {
        var calls: [Call] = []
        var trusts: [ServerTrust] = []
        var caPEM: @Sendable (URL) throws -> String
        var health: @Sendable (URL) throws -> String = { _ in "1.0.0" }
        var pair: @Sendable (URL) throws -> PairedDevice = { _ in FakeBrievieServer.device }
        var revoke: @Sendable (URL) async throws -> Void = { _ in }
    }

    private let state: Mutex<State>

    init() throws {
        let pem = try Fixtures.text("ca.pem")
        state = Mutex(State(caPEM: { _ in pem }))
    }

    var calls: [Call] { state.withLock { $0.calls } }
    var trusts: [ServerTrust] { state.withLock { $0.trusts } }

    var caPEM: @Sendable (URL) throws -> String {
        get { state.withLock { $0.caPEM } }
        set { state.withLock { $0.caPEM = newValue } }
    }

    var health: @Sendable (URL) throws -> String {
        get { state.withLock { $0.health } }
        set { state.withLock { $0.health = newValue } }
    }

    var pair: @Sendable (URL) throws -> PairedDevice {
        get { state.withLock { $0.pair } }
        set { state.withLock { $0.pair = newValue } }
    }

    /// Async, so a test can make the server hang (until the call is cancelled).
    var revoke: @Sendable (URL) async throws -> Void {
        get { state.withLock { $0.revoke } }
        set { state.withLock { $0.revoke = newValue } }
    }

    var revokeCalls: [Call] { calls.filter { if case .revoke = $0 { true } else { false } } }

    func caCertificatePEM(at url: URL) async throws -> String {
        let answer = state.withLock {
            $0.calls.append(.caCertificate(url))
            return $0.caPEM
        }
        return try answer(url)
    }

    func health(at url: URL, trust: ServerTrust) async throws -> String {
        let answer = state.withLock {
            $0.calls.append(.health(url))
            $0.trusts.append(trust)
            return $0.health
        }
        return try answer(url)
    }

    func pair(at url: URL, trust: ServerTrust, code: String, deviceName: String) async throws -> PairedDevice {
        let answer = state.withLock {
            $0.calls.append(.pair(url, code: code, name: deviceName))
            $0.trusts.append(trust)
            return $0.pair
        }
        return try answer(url)
    }

    func revokeDevice(_ deviceID: UUID, at url: URL, trust: ServerTrust, token: String) async throws {
        let answer = state.withLock {
            $0.calls.append(.revoke(url, deviceID: deviceID, token: token))
            $0.trusts.append(trust)
            return $0.revoke
        }
        try await answer(url)
    }

    func workspaces(at url: URL, trust: ServerTrust, token: String) async throws -> [WorkspaceSummary] {
        Issue.record("PairingService must not list workspaces")
        return []
    }
}

/// A fake server, an in-memory store and a two-URL payload (home first, then away) for `PairingService` tests.
struct PairingHarness {
    let secrets: any SecretStore = InMemorySecretStore()
    let server: FakeBrievieServer
    let home: URL
    let away: URL

    init() throws {
        server = try FakeBrievieServer()
        home = try #require(URL(string: "https://brievie.local:8443"))
        away = try #require(URL(string: "https://brievie.example.nl"))
    }

    var store: ConnectionStore { ConnectionStore(secrets: secrets) }
    var service: PairingService { PairingService(server: server, store: store) }

    func payload(caSHA256: String?) throws -> PairingPayload {
        let hash = caSHA256.map { "\"\($0)\"" } ?? "null"
        return try PairingPayload.parse(
            #"{"v":1,"urls":["\#(home)","\#(away)"],"code":"ABCD-EFGH","ca_sha256":\#(hash)}"#
        )
    }

    func pinnedPayload() throws -> PairingPayload {
        try payload(caSHA256: try Fixtures.text("ca.sha256").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func pair(name: String = "iPhone") async throws(PairingError) -> ServerConnection {
        let payload: PairingPayload
        do {
            payload = try pinnedPayload()
        } catch {
            Issue.record("Bad test payload: \(error)")
            throw .failed("test setup")
        }
        return try await service.pair(payload, deviceName: name)
    }

    func expectNothingStored(sourceLocation: SourceLocation = #_sourceLocation) throws {
        #expect(try store.load() == nil, sourceLocation: sourceLocation)
        #expect(try secrets.read(.serverConnection) == nil, sourceLocation: sourceLocation)
        #expect(try secrets.read(.deviceToken) == nil, sourceLocation: sourceLocation)
    }
}

/// Stores in memory but fails every device-token write.
final class TokenWriteFailingStore: SecretStore {
    struct WriteFailed: Error {}

    private let inner = InMemorySecretStore()

    func read(_ key: SecretKey) throws -> Data? {
        inner.read(key)
    }

    func write(_ data: Data, for key: SecretKey) throws {
        if key == .deviceToken { throw WriteFailed() }
        inner.write(data, for: key)
    }

    func delete(_ key: SecretKey) throws {
        inner.delete(key)
    }
}
