import BrievieCore
import SwiftUI
import UIKit

@main
struct BrievieApp: App {
    @State private var appModel: AppModel
    private let environment: AppEnvironment

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let store = ConnectionStore(secrets: KeychainSecretStore())
        let launchFlag = UserDefaultsLaunchFlag()
        let model = AppModel(
            store: store,
            authenticator: LocalAuthenticator(),
            launchFlag: launchFlag,
            // False before the first unlock after a reboot (prewarm, background launch).
            isProtectedDataAvailable: { UIApplication.shared.isProtectedDataAvailable }
        )
        model.start()
        _appModel = State(initialValue: model)
        // An upload that gets a 401 sends the user back to pairing, like any other call.
        environment = AppEnvironment.live(store: store) { [model] deviceID in
            await model.sessionRevoked(deviceID: deviceID)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(appModel: appModel, environment: environment)
        }
    }
}
