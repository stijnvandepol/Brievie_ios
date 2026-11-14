@testable import BrievieCore
import Foundation
import Testing
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

@Suite struct DeviceAuthenticationTests {
    #if canImport(LocalAuthentication)
    @Test func onlyPasscodeNotSetMeansNoPasscode() {
        let noPasscode = NSError(domain: LAError.errorDomain, code: LAError.passcodeNotSet.rawValue)
        #expect(LocalAuthenticator.availability(for: noPasscode) == .noPasscode)
    }

    @Test(arguments: [
        LAError.biometryNotAvailable, .biometryNotEnrolled, .biometryLockout, .systemCancel, .notInteractive
    ])
    func everyOtherLocalAuthenticationErrorIsUnavailable(code: LAError.Code) {
        let error = NSError(domain: LAError.errorDomain, code: code.rawValue)
        #expect(LocalAuthenticator.availability(for: error) == .unavailable)
    }

    @Test func anUnknownErrorOrNoErrorIsUnavailable() {
        let foreign = NSError(domain: "other", code: LAError.passcodeNotSet.rawValue)
        #expect(LocalAuthenticator.availability(for: foreign) == .unavailable)
        #expect(LocalAuthenticator.availability(for: nil) == .unavailable)
    }
    #endif

    @Test func theLaunchFlagPersistsInItsSuite() throws {
        let suite = "nl.stijnvdpol.brievie.tests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let flag = UserDefaultsLaunchFlag(suiteName: suite)
        #expect(!flag.hasLaunchedBefore)

        flag.markLaunched()

        #expect(UserDefaultsLaunchFlag(suiteName: suite).hasLaunchedBefore)
    }
}
