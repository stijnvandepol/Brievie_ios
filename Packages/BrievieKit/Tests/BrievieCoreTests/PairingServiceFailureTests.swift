@testable import BrievieCore
import Foundation
import Testing

/// Pairings that fail: nothing may be stored, and the pairing code never goes to a second URL.
@Suite struct PairingServiceFailureTests {
    private let harness: PairingHarness
    private var server: FakeBrievieServer { harness.server }
    private var home: URL { harness.home }
    private var away: URL { harness.away }

    init() throws {
        harness = try PairingHarness()
    }

    // MARK: - Review Focus 2: no URL can be verified

    @Test func allURLsWithTheWrongCAFailAsNotVerified() async throws {
        let otherCA = try Fixtures.text("other-ca.pem")
        server.caPEM = { _ in otherCA }

        await #expect(throws: PairingError.serverNotVerified) { try await harness.pair() }

        #expect(server.calls == [.caCertificate(home), .caCertificate(away)])
        try harness.expectNothingStored()
    }

    @Test func mismatchThenUnreachableFailsAsNotVerified() async throws {
        let home = home
        let otherCA = try Fixtures.text("other-ca.pem")
        server.caPEM = { url in
            if url == home { return otherCA }
            throw ServerError.unreachable
        }

        await #expect(throws: PairingError.serverNotVerified) { try await harness.pair() }

        #expect(server.calls.filter(\.isPair).isEmpty)
        try harness.expectNothingStored()
    }

    @Test func untrustedEverywhereFailsAsNotVerified() async throws {
        server.health = { _ in throw ServerError.untrusted }

        await #expect(throws: PairingError.serverNotVerified) { try await harness.pair() }

        #expect(server.calls.filter(\.isPair).isEmpty)
        try harness.expectNothingStored()
    }

    // MARK: - Review Focus 4: nothing reachable

    @Test func allUnreachableFailsAndStoresNothing() async throws {
        server.caPEM = { _ in throw ServerError.unreachable }

        await #expect(throws: PairingError.noServerReachable) { try await harness.pair() }

        #expect(server.calls == [.caCertificate(home), .caCertificate(away)])
        try harness.expectNothingStored()
    }

    // MARK: - Stops immediately

    @Test(arguments: ["2.0.0", "0.9.0", "", "one"])
    func otherMajorVersionStopsAtOnce(apiVersion: String) async throws {
        server.health = { _ in apiVersion }

        await #expect(throws: PairingError.incompatibleServer) { try await harness.pair() }

        #expect(server.calls == [.caCertificate(home), .health(home)])
        try harness.expectNothingStored()
    }

    @Test(arguments: [
        (ServerError.invalidCode, PairingError.invalidCode),
        (.tooManyAttempts, .tooManyAttempts),
        (.unreachable, .connectionLostWhilePairing),
        (.untrusted, .connectionLostWhilePairing)
    ])
    func failedPairNeverSendsTheCodeToAnotherURL(error: ServerError, expected: PairingError) async throws {
        server.pair = { _ in throw error }

        await #expect(throws: expected) { try await harness.pair() }

        #expect(server.calls.filter(\.isPair) == [.pair(home, code: "ABCD-EFGH", name: "iPhone")])
        #expect(!server.calls.contains(.caCertificate(away)))
        try harness.expectNothingStored()
    }

    @Test func emptyTokenIsIncompatible() async throws {
        server.pair = { _ in PairedDevice(deviceID: UUID(), token: "", userName: "Beheerder") }

        await #expect(throws: PairingError.incompatibleServer) { try await harness.pair() }

        try harness.expectNothingStored()
    }

    @Test func storageFailureLeavesNothingStored() async throws {
        let failing = TokenWriteFailingStore()
        let service = PairingService(server: server, store: ConnectionStore(secrets: failing))

        let error = await #expect(throws: PairingError.self) {
            try await service.pair(try harness.pinnedPayload(), deviceName: "iPhone")
        }

        guard case .failed = error else {
            Issue.record("Expected .failed, got \(String(describing: error))")
            return
        }
        #expect(try failing.read(.serverConnection) == nil)
        #expect(try failing.read(.deviceToken) == nil)
    }

    // MARK: - Cancellation

    @Test func cancellationDuringCAFetchStopsWithoutTryingOtherURLs() async throws {
        // What URLSession does when the task is cancelled mid-request; must not read as "not verified".
        server.caPEM = { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            throw ServerError.untrusted
        }

        await #expect(throws: PairingError.cancelled) { try await harness.pair() }

        #expect(server.calls == [.caCertificate(home)])
        try harness.expectNothingStored()
    }

    @Test func cancellationErrorFromHealthStops() async throws {
        server.health = { _ in throw CancellationError() }

        await #expect(throws: PairingError.cancelled) { try await harness.pair() }

        #expect(server.calls == [.caCertificate(home), .health(home)])
        try harness.expectNothingStored()
    }

    @Test func cancellationAfterTheLastURLIsCancelledNotNotVerified() async throws {
        // The cancel lands while the last URL answers with a CA that does not match: the answer itself is a
        // success for the transport, so only the check after the loop can tell this is a cancelled pairing.
        let away = away
        let otherCA = try Fixtures.text("other-ca.pem")
        server.caPEM = { url in
            if url == away { withUnsafeCurrentTask { $0?.cancel() } }
            return otherCA
        }

        await #expect(throws: PairingError.cancelled) { try await harness.pair() }

        try harness.expectNothingStored()
    }

    @Test func alreadyCancelledTaskContactsNoServer() async throws {
        let harness = harness
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await harness.pair()
        }

        await #expect(throws: PairingError.cancelled) { try await task.value }

        #expect(server.calls.isEmpty)
        try harness.expectNothingStored()
    }
}
