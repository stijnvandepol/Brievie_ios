import BrievieCore
import Foundation
import Synchronization

/// A `BrievieServer` for pairing tests: every URL answers as a public-certificate server unless set otherwise.
/// It records the codes and proofs it receives, so a test can check that the link path never sends the code.
final class StubServer: BrievieServer {
    private struct State {
        var healthCalls = 0
        var pairCalls = 0
        var challengeCalls = 0
        var proofCalls = 0
        var deviceNames: [String] = []
        var codes: [String] = []
        var proofs: [CodeProof] = []
        var health: @Sendable () throws -> String = { "1.0.0" }
        var pair: @Sendable () throws -> PairedDevice = { StubServer.device }
        var challenge: @Sendable () throws -> String = { StubServer.nonce }
        var proof: @Sendable () async throws -> PairedDevice = { StubServer.device }
    }

    static let device = PairedDevice(deviceID: UUID(), token: "device-token", userName: "Beheerder")
    static let nonce = "q3Vb8xN2pL5sT9wE1yH4kM7rC0uZ6aJdFgQiXoWnYeK"

    private let state = Mutex(State())

    var healthCalls: Int { state.withLock { $0.healthCalls } }
    var pairCalls: Int { state.withLock { $0.pairCalls } }
    var challengeCalls: Int { state.withLock { $0.challengeCalls } }
    var proofCalls: Int { state.withLock { $0.proofCalls } }
    var deviceNames: [String] { state.withLock { $0.deviceNames } }
    /// Every code received by `pair` (the QR path).
    var codes: [String] { state.withLock { $0.codes } }
    var proofs: [CodeProof] { state.withLock { $0.proofs } }

    var health: @Sendable () throws -> String {
        get { state.withLock { $0.health } }
        set { state.withLock { $0.health = newValue } }
    }

    var pair: @Sendable () throws -> PairedDevice {
        get { state.withLock { $0.pair } }
        set { state.withLock { $0.pair = newValue } }
    }

    var challenge: @Sendable () throws -> String {
        get { state.withLock { $0.challenge } }
        set { state.withLock { $0.challenge = newValue } }
    }

    /// Async, so a test can hold the proof call open.
    var proof: @Sendable () async throws -> PairedDevice {
        get { state.withLock { $0.proof } }
        set { state.withLock { $0.proof = newValue } }
    }

    func health(at url: URL, trust: ServerTrust) async throws -> String {
        let answer = state.withLock {
            $0.healthCalls += 1
            return $0.health
        }
        return try answer()
    }

    func caCertificatePEM(at url: URL) async throws -> String {
        throw ServerError.other("not expected: the payload has no CA")
    }

    func pair(at url: URL, trust: ServerTrust, code: String, deviceName: String) async throws -> PairedDevice {
        let answer = state.withLock {
            $0.pairCalls += 1
            $0.deviceNames.append(deviceName)
            $0.codes.append(code)
            return $0.pair
        }
        return try answer()
    }

    func pairingChallenge(at url: URL, trust: ServerTrust) async throws -> String {
        let answer = state.withLock {
            $0.challengeCalls += 1
            return $0.challenge
        }
        return try answer()
    }

    func pairWithProof(
        at url: URL, trust: ServerTrust, proof: CodeProof, deviceName: String
    ) async throws -> PairedDevice {
        let answer = state.withLock {
            $0.proofCalls += 1
            $0.deviceNames.append(deviceName)
            $0.proofs.append(proof)
            return $0.proof
        }
        return try await answer()
    }

    func workspaces(at url: URL, trust: ServerTrust, token: String) async throws -> [WorkspaceSummary] {
        []
    }

    func revokeDevice(_ deviceID: UUID, at url: URL, trust: ServerTrust, token: String) async throws {
        throw ServerError.other("not expected: pairing never revokes")
    }
}

/// Holds a call open until the test lets it go.
final class Gate: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let entered: AsyncStream<Void>.Continuation
    let arrivals: AsyncStream<Void>

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        (arrivals, entered) = AsyncStream.makeStream(of: Void.self)
    }

    /// Called by the server; returns once `open()` was called.
    func pass() async {
        entered.yield()
        for await _ in stream { return }
    }

    func open() {
        continuation.yield()
        continuation.finish()
    }

    /// Waits until a call reached the gate.
    func waitForArrival() async {
        for await _ in arrivals { return }
    }
}
