import BrievieCore
import Foundation

/// What the app talks to: the Keychain-backed connection store, the live server client and the upload queue.
struct AppEnvironment {
    let store: ConnectionStore
    let server: any BrievieServer
    let documents: any DocumentServer
    let launchFlag: any LaunchFlag
    let uploads: UploadCoordinator
    /// "Ontkoppelen": the live server and the upload queue.
    let unpairing: Unpairing

    /// - Parameter onRevoked: called when an upload finds that the server no longer knows this device.
    @MainActor
    static func live(store: ConnectionStore, onRevoked: @escaping @Sendable (UUID) async -> Void) -> AppEnvironment {
        let transport = BackgroundUploadTransport(trustProvider: StoredConnectionTrustProvider(store: store))
        // Created at launch, also in the background: the system delivers upload events to this session.
        transport.activate()
        let uploads = UploadCoordinator(
            store: UploadQueueStore(directory: uploadsDirectory),
            transport: transport,
            connection: { try store.load().map { ($0.connection, $0.token) } },
            onRevoked: onRevoked
        )
        AppDelegate.uploads = uploads
        Task { await uploads.run() }
        let server = LiveBrievieServer()
        return AppEnvironment(
            store: store, server: server, documents: server, launchFlag: UserDefaultsLaunchFlag(), uploads: uploads,
            unpairing: Unpairing(server: server, uploads: uploads)
        )
    }

    /// Scans waiting for upload. Not in a cache directory: the system may empty those.
    private static var uploadsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Uploads", directoryHint: .isDirectory)
    }
}
