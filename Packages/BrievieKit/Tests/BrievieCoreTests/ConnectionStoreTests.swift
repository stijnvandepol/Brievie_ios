@testable import BrievieCore
import Foundation
import Synchronization
import Testing

@Suite struct ConnectionStoreTests {
    private let secrets: any SecretStore = InMemorySecretStore()
    private var store: ConnectionStore { ConnectionStore(secrets: secrets) }

    private func connection() throws -> ServerConnection {
        ServerConnection(
            urls: [
                try #require(URL(string: "https://brievie.local:8443")),
                try #require(URL(string: "https://brievie.example.nl"))
            ],
            caCertificateDER: Data([0x30, 0x82, 0x01, 0x0A]),
            deviceID: UUID(),
            userName: "Stijn"
        )
    }

    @Test func emptyStoreLoadsNil() throws {
        #expect(try store.load() == nil)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let saved = try connection()

        try store.save(saved, token: "device-token-123")
        let loaded = try #require(try store.load())

        #expect(loaded.connection == saved)
        #expect(loaded.token == "device-token-123")
    }

    @Test func roundTripsWithoutCACertificate() throws {
        let original = try connection()
        let saved = ServerConnection(
            urls: original.urls, caCertificateDER: nil, deviceID: original.deviceID, userName: original.userName
        )

        try store.save(saved, token: "t")

        #expect(try store.load()?.connection == saved)
    }

    @Test func clearRemovesEverything() throws {
        try store.save(try connection(), token: "device-token-123")

        try store.clear()

        #expect(try store.load() == nil)
        #expect(try secrets.read(.deviceToken) == nil)
        #expect(try secrets.read(.serverConnection) == nil)
    }

    @Test func onlyTokenLoadsNilAndRemovesToken() throws {
        try secrets.write(Data("device-token-123".utf8), for: .deviceToken)

        #expect(try store.load() == nil)
        #expect(try secrets.read(.deviceToken) == nil)
    }

    @Test func onlyConnectionLoadsNilAndRemovesConnection() throws {
        try store.save(try connection(), token: "device-token-123")
        try secrets.delete(.deviceToken)

        #expect(try store.load() == nil)
        #expect(try secrets.read(.serverConnection) == nil)
    }

    @Test func unreadableConnectionLoadsNilAndClearsBoth() throws {
        try secrets.write(Data("not json".utf8), for: .serverConnection)
        try secrets.write(Data("device-token-123".utf8), for: .deviceToken)

        #expect(try store.load() == nil)
        #expect(try secrets.read(.deviceToken) == nil)
        #expect(try secrets.read(.serverConnection) == nil)
    }

    @Test func emptyTokenIsRefusedAndNothingIsStored() throws {
        #expect(throws: ConnectionStoreError.emptyToken) {
            try store.save(try connection(), token: "")
        }
        #expect(try store.load() == nil)
        #expect(try secrets.read(.serverConnection) == nil)
    }

    @Test func emptyTokenKeepsExistingPairing() throws {
        let existing = try connection()
        try store.save(existing, token: "old-token")

        #expect(throws: ConnectionStoreError.emptyToken) {
            try store.save(try connection(), token: "")
        }
        #expect(try store.load()?.connection == existing)
    }

    @Test func failedTokenWriteWhileRepairingLeavesNoPairing() throws {
        let failing = FailingTokenWriteStore()
        let store = ConnectionStore(secrets: failing)
        try store.save(try connection(), token: "old-server-token")

        failing.failTokenWrites = true
        #expect(throws: FailingTokenWriteStore.WriteFailed.self) {
            try store.save(try connection(), token: "new-server-token")
        }

        #expect(try store.load() == nil)
        #expect(try failing.read(.serverConnection) == nil)
        #expect(try failing.read(.deviceToken) == nil)
    }
}

/// Stores in memory, but can be told to fail every device-token write.
private final class FailingTokenWriteStore: SecretStore {
    struct WriteFailed: Error {}

    private let inner = InMemorySecretStore()
    private let failing = Mutex(false)

    var failTokenWrites: Bool {
        get { failing.withLock { $0 } }
        set { failing.withLock { $0 = newValue } }
    }

    func read(_ key: SecretKey) throws -> Data? {
        inner.read(key)
    }

    func write(_ data: Data, for key: SecretKey) throws {
        if key == .deviceToken, failTokenWrites {
            throw WriteFailed()
        }
        inner.write(data, for: key)
    }

    func delete(_ key: SecretKey) throws {
        inner.delete(key)
    }
}
