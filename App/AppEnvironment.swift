import BrievieCore

/// What the app talks to: the Keychain-backed connection store and the live server client.
struct AppEnvironment {
    let store: ConnectionStore
    let server: any BrievieServer
    let launchFlag: any LaunchFlag

    static var live: AppEnvironment {
        AppEnvironment(
            store: ConnectionStore(secrets: KeychainSecretStore()),
            server: LiveBrievieServer(),
            launchFlag: UserDefaultsLaunchFlag()
        )
    }
}
