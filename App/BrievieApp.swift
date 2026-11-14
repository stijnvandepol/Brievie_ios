import BrievieCore
import SwiftUI
import UIKit

@main
struct BrievieApp: App {
    @State private var appModel: AppModel
    private let environment: AppEnvironment

    init() {
        let environment = AppEnvironment.live
        self.environment = environment
        let model = AppModel(
            store: environment.store,
            authenticator: LocalAuthenticator(),
            launchFlag: environment.launchFlag,
            // False before the first unlock after a reboot (prewarm, background launch).
            isProtectedDataAvailable: { UIApplication.shared.isProtectedDataAvailable }
        )
        model.start()
        _appModel = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView(appModel: appModel, environment: environment)
        }
    }
}
