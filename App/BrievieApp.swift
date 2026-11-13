import BrievieCore
import SwiftUI

@main
struct BrievieApp: App {
    @State private var appModel: AppModel
    private let environment: AppEnvironment

    init() {
        let environment = AppEnvironment.live
        self.environment = environment
        let model = AppModel(store: environment.store, authenticator: LocalAuthenticator())
        model.start()
        _appModel = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView(appModel: appModel, environment: environment)
        }
    }
}
