import BrievieCore
import SwiftUI
import UIKit

@main
struct BrievieApp: App {
    @State private var appModel: AppModel
    private let environment: AppEnvironment
    /// Hides the paired app while it is not active (the app switcher's snapshot); pairing shows no personal data.
    private let privacyCover: PrivacyCoverWindow

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let store = ConnectionStore(secrets: KeychainSecretStore())
        let launchFlag = UserDefaultsLaunchFlag()
        let server = LiveBrievieServer()
        let calendar = AppCalendar(store: store, server: server, settings: UserDefaultsCalendarSettings())
        let model = AppModel(
            store: store,
            authenticator: LocalAuthenticator(),
            launchFlag: launchFlag,
            // False before the first unlock after a reboot (prewarm, background launch).
            isProtectedDataAvailable: { UIApplication.shared.isProtectedDataAvailable },
            // A revoked or unpaired pairing turns every calendar switch off; a revocation also removes the
            // calendars (a revoked phone may be a stolen one).
            calendarSettings: calendar.settings,
            calendarSync: calendar.sync
        )
        model.start()
        _appModel = State(initialValue: model)
        privacyCover = PrivacyCoverWindow { [model] in
            if case .unpaired = model.state { return false }
            return true
        }
        // An upload that gets a 401 sends the user back to pairing, like any other call.
        environment = AppEnvironment.live(store: store, server: server, calendar: calendar) { [model] deviceID in
            await model.sessionRevoked(deviceID: deviceID)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(appModel: appModel, environment: environment)
        }
    }
}
