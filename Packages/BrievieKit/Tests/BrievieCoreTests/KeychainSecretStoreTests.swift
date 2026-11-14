import BrievieCore
import Foundation
import Testing

/// The Keychain needs an entitled process: an unhosted package test bundle on the simulator gets
/// `errSecMissingEntitlement` (-34018), and plain `swift test` on macOS has no entitlements either.
/// These tests therefore run inside the app on the simulator, via the `BrievieTests` target in
/// `project.yml` (`make test-keychain`), which compiles this file with `BRIEVIE_HOSTED_TESTS`.
/// There they always run, and `hostIsTheAppOnSimulator` fails when the host is wrong, so that run can
/// never pass with zero Keychain tests. Everywhere else they are reported as skipped.
private var runsInsideAppOnSimulator: Bool {
    #if targetEnvironment(simulator)
    Bundle.main.bundleIdentifier == "nl.stijnvdpol.brievie"
    #else
    false
    #endif
}

#if BRIEVIE_HOSTED_TESTS
private let keychainTestsEnabled = true
#else
private let keychainTestsEnabled = runsInsideAppOnSimulator
#endif

@Suite(.enabled(if: keychainTestsEnabled, "Needs the app's Keychain on the simulator (make test-keychain)"))
struct KeychainSecretStoreTests {
    @Test func hostIsTheAppOnSimulator() {
        #expect(runsInsideAppOnSimulator, "Keychain tests must run hosted in nl.stijnvdpol.brievie on the simulator")
    }

    @Test func roundTripOverwriteAndDelete() throws {
        let store = KeychainSecretStore(service: "nl.stijnvdpol.brievie.tests.\(UUID().uuidString)")
        defer {
            try? store.delete(.deviceToken)
            try? store.delete(.serverConnection)
        }

        #expect(try store.read(.deviceToken) == nil)

        try store.write(Data("first".utf8), for: .deviceToken)
        #expect(try store.read(.deviceToken) == Data("first".utf8))
        #expect(try store.read(.serverConnection) == nil)

        try store.write(Data("second".utf8), for: .deviceToken)
        #expect(try store.read(.deviceToken) == Data("second".utf8))

        try store.delete(.deviceToken)
        #expect(try store.read(.deviceToken) == nil)

        // Deleting a missing item is not an error.
        try store.delete(.deviceToken)
    }

    @Test func servicesAreIsolated() throws {
        let first = KeychainSecretStore(service: "nl.stijnvdpol.brievie.tests.\(UUID().uuidString)")
        let second = KeychainSecretStore(service: "nl.stijnvdpol.brievie.tests.\(UUID().uuidString)")
        defer { try? first.delete(.deviceToken) }

        try first.write(Data("token".utf8), for: .deviceToken)

        #expect(try second.read(.deviceToken) == nil)
    }
}
