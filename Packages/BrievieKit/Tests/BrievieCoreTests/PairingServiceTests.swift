@testable import BrievieCore
import Foundation
import Synchronization
import Testing

@Suite struct PairingServiceTests {
    private let secrets: any SecretStore = InMemorySecretStore()
    private var store: ConnectionStore { ConnectionStore(secrets: secrets) }

    private static let home = URL(string: "https://brievie.local:8443")
    private static let away = URL(string: "https://brievie.example.nl")

    private func urls() throws -> (home: URL, away: URL) {
        (try #require(Self.home), try #require(Self.away))
    }

    private func payload(caSHA256: String?) throws -> PairingPayload {
        let (home, away) = try urls()
        let hash = caSHA256.map { "\"\($0)\"" } ?? "null"
        return try PairingPayload.parse(
            #"{"v":1,"urls":["\#(home)","\#(away)"],"code":"ABCD-EFGH","ca_sha256":\#(hash)}"#
        )
    }

    private func pinnedPayload() throws -> PairingPayload {
        try payload(caSHA256: try Fixtures.text("ca.sha256").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func service(_ server: FakeBrievieServer) -> PairingService {
        PairingService(server: server, store: store)
    }

    private func expectNothingStored() throws {
        #expect(try store.load() == nil)
        #expect(try secrets.read(.serverConnection) == nil)
        #expect(try secrets.read(.deviceToken) == nil)
    }

    // MARK: - Happy path

    @Test func pairsAndStoresConnectionAndToken() async throws {
        let server = try FakeBrievieServer()
        let (home, away) = try urls()

        let connection = try await service(server).pair(try pinnedPayload(), deviceName: "iPhone van Stijn")

        let expected = ServerConnection(
            urls: [home, away],
            caCertificateDER: try Fixtures.der("ca.pem"),
            deviceID: FakeBrievieServer.device.deviceID,
            userName: FakeBrievieServer.device.userName
        )
        #expect(connection == expected)
        let stored = try #require(try store.load())
        #expect(stored.connection == expected)
        #expect(stored.token == FakeBrievieServer.device.token)
        #expect(server.calls == [
            .caCertificate(home), .health(home), .pair(home, code: "ABCD-EFGH", name: "iPhone van Stijn")
        ])
    }

    @Test func healthAndPairUseTrustPinnedToTheVerifiedCA() async throws {
        let server = try FakeBrievieServer()

        _ = try await service(server).pair(try pinnedPayload(), deviceName: "iPhone")

        let trusts = server.trusts
        #expect(trusts.count == 2)
        for trust in trusts {
            #expect(trust.evaluate(try Fixtures.serverTrust(leaf: "leaf-a.pem"), host: "localhost"))
            #expect(!trust.evaluate(try Fixtures.serverTrust(leaf: "other-leaf.pem"), host: "localhost"))
        }
    }

    @Test(arguments: ["1.0.0", "1.7.3"])
    func acceptsAnyVersionOne(apiVersion: String) async throws {
        let server = try FakeBrievieServer()
        server.health = { _ in apiVersion }

        _ = try await service(server).pair(try pinnedPayload(), deviceName: "iPhone")

        #expect(try store.load() != nil)
    }

    // MARK: - Review Focus 2: fingerprint mismatch

    @Test func fingerprintMismatchStopsAndStoresNothing() async throws {
        let server = try FakeBrievieServer()
        server.caPEM = { _ in try Fixtures.text("other-ca.pem") }
        let (home, _) = try urls()

        await #expect(throws: PairingError.serverNotVerified) {
            try await service(server).pair(try pinnedPayload(), deviceName: "iPhone")
        }

        #expect(server.calls == [.caCertificate(home)])
        try expectNothingStored()
    }

    @Test func malformedCertificateStopsAndStoresNothing() async throws {
        let server = try FakeBrievieServer()
        server.caPEM = { _ in "not a certificate" }
        let (home, _) = try urls()

        await #expect(throws: PairingError.serverNotVerified) {
            try await service(server).pair(try pinnedPayload(), deviceName: "iPhone")
        }

        #expect(server.calls == [.caCertificate(home)])
        try expectNothingStored()
    }

    @Test func untrustedServerStopsAndStoresNothing() async throws {
        let server = try FakeBrievieServer()
        server.health = { _ in throw ServerError.untrusted }
        let (home, _) = try urls()

        await #expect(throws: PairingError.serverNotVerified) {
            try await service(server).pair(try pinnedPayload(), deviceName: "iPhone")
        }

        #expect(server.calls == [.caCertificate(home), .health(home)])
        try expectNothingStored()
    }

    // MARK: - Review Focus 4: trying the next URL

    @Test func unreachableCAFetchMovesToNextURL() async throws {
        let server = try FakeBrievieServer()
        let (home, away) = try urls()
        server.caPEM = { url in
            if url == home { throw ServerError.unreachable }
            return try Fixtures.text("ca.pem")
        }

        let connection = try await service(server).pair(try pinnedPayload(), deviceName: "iPhone")

        #expect(connection.urls == [home, away])
        #expect(try store.load()?.connection.urls == [home, away])
        #expect(server.calls == [
            .caCertificate(home), .caCertificate(away), .health(away), .pair(away, code: "ABCD-EFGH", name: "iPhone")
        ])
    }

    @Test func unreachableHealthMovesToNextURL() async throws {
        let server = try FakeBrievieServer()
        let (home, away) = try urls()
        server.health = { url in
            if url == home { throw ServerError.unreachable }
            return "1.0.0"
        }

        let connection = try await service(server).pair(try pinnedPayload(), deviceName: "iPhone")

        #expect(connection.urls == [home, away])
        #expect(try store.load()?.connection.urls == [home, away])
        #expect(server.calls.last == .pair(away, code: "ABCD-EFGH", name: "iPhone"))
    }

    @Test func allUnreachableFailsAndStoresNothing() async throws {
        let server = try FakeBrievieServer()
        server.caPEM = { _ in throw ServerError.unreachable }
        let (home, away) = try urls()

        await #expect(throws: PairingError.noServerReachable) {
            try await service(server).pair(try pinnedPayload(), deviceName: "iPhone")
        }

        #expect(server.calls == [.caCertificate(home), .caCertificate(away)])
        try expectNothingStored()
    }

    @Test func unreachableWhilePairingDoesNotRetryTheCodeElsewhere() async throws {
        let server = try FakeBrievieServer()
        server.pair = { _ in throw ServerError.unreachable }
        let (home, _) = try urls()

        await #expect(throws: PairingError.noServerReachable) {
            try await service(server).pair(try pinnedPayload(), deviceName: "iPhone")
        }

        #expect(server.calls.filter(\.isPair) == [.pair(home, code: "ABCD-EFGH", name: "iPhone")])
        try expectNothingStored()
    }

    // MARK: - Server refusals

    @Test func invalidCodeStoresNothing() async throws {
        let server = try FakeBrievieServer()
        server.pair = { _ in throw ServerError.invalidCode }

        await #expect(throws: PairingError.invalidCode) {
            try await service(server).pair(try pinnedPayload(), deviceName: "iPhone")
        }

        try expectNothingStored()
    }

    @Test func tooManyAttemptsStoresNothing() async throws {
        let server = try FakeBrievieServer()
        server.pair = { _ in throw ServerError.tooManyAttempts }

        await #expect(throws: PairingError.tooManyAttempts) {
            try await service(server).pair(try pinnedPayload(), deviceName: "iPhone")
        }

        try expectNothingStored()
    }

    @Test(arguments: ["2.0.0", "0.9.0", "", "one"])
    func otherMajorVersionIsIncompatible(apiVersion: String) async throws {
        let server = try FakeBrievieServer()
        server.health = { _ in apiVersion }

        await #expect(throws: PairingError.incompatibleServer) {
            try await service(server).pair(try pinnedPayload(), deviceName: "iPhone")
        }

        #expect(server.calls.filter(\.isPair).isEmpty)
        try expectNothingStored()
    }

    @Test func storageFailureLeavesNothingStored() async throws {
        let server = try FakeBrievieServer()
        let failing = TokenWriteFailingStore()
        let service = PairingService(server: server, store: ConnectionStore(secrets: failing))

        await #expect(throws: PairingError.self) {
            try await service.pair(try pinnedPayload(), deviceName: "iPhone")
        }

        #expect(try failing.read(.serverConnection) == nil)
        #expect(try failing.read(.deviceToken) == nil)
    }

    // MARK: - Public certificate (no CA in the QR code)

    @Test func withoutCAFingerprintSkipsCAFetchAndUsesSystemTrust() async throws {
        let server = try FakeBrievieServer()
        let (home, _) = try urls()

        let connection = try await service(server).pair(try payload(caSHA256: nil), deviceName: "iPhone")

        #expect(!server.calls.contains(.caCertificate(home)))
        #expect(server.calls.first == .health(home))
        #expect(connection.caCertificateDER == nil)
        #expect(try store.load()?.connection.caCertificateDER == nil)
        // System trust: the privately signed fixture leaf is refused.
        let trust = try #require(server.trusts.first)
        #expect(!trust.evaluate(try Fixtures.serverTrust(leaf: "leaf-a.pem"), host: "localhost"))
    }
}

// MARK: - Fakes

/// A `BrievieServer` whose answers are set per test and which records every call.
private final class FakeBrievieServer: BrievieServer {
    enum Call: Equatable {
        case caCertificate(URL)
        case health(URL)
        case pair(URL, code: String, name: String)

        var isPair: Bool {
            if case .pair = self { true } else { false }
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

    func workspaces(at url: URL, trust: ServerTrust, token: String) async throws -> [WorkspaceSummary] {
        Issue.record("PairingService must not list workspaces")
        return []
    }
}

/// Stores in memory but fails every device-token write.
private final class TokenWriteFailingStore: SecretStore {
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
