@testable import BrievieCore
import Foundation
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
}
