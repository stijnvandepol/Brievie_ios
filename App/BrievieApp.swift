import BrievieCore
import FeaturePairing
import SwiftUI
import UIKit

@main
struct BrievieApp: App {
    @State private var appModel: AppModel
    /// The sheet of a `brievie://server` link. Owns its pairing task, so it lives as long as the app.
    @State private var linkModel: ServerLinkModel
    private let environment: AppEnvironment
    /// Hides the paired app while it is not active (the app switcher's snapshot), and the link sheet while it asks
    /// for the pairing code; the rest of pairing shows no personal data.
    private let privacyCover: PrivacyCoverWindow

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let store = ConnectionStore(secrets: KeychainSecretStore())
        let launchFlag = UserDefaultsLaunchFlag()
        let server = LiveBrievieServer()
        let calendar = AppCalendar(store: store, server: server, settings: UserDefaultsCalendarSettings())
        let currentWorkspace = UserDefaultsCurrentWorkspaceStore()
        // Local notifications for deadlines, made on the phone from the tasks the app read; nothing goes to a server.
        let reminders = DeadlineReminders(
            center: UserNotificationsReminderCenter(), settings: UserDefaultsReminderSettings(),
            tasks: AppCalendar.openTasks(store: store, server: server)
        )
        let reminderRouter = ReminderRouter()
        AppDelegate.reminderRouter = reminderRouter
        let model = AppModel(
            store: store,
            authenticator: LocalAuthenticator(),
            launchFlag: launchFlag,
            // False before the first unlock after a reboot (prewarm, background launch).
            isProtectedDataAvailable: { UIApplication.shared.isProtectedDataAvailable },
            // A revoked or unpaired pairing turns every calendar switch off; a revocation also removes the
            // calendars (a revoked phone may be a stolen one).
            calendarSettings: calendar.settings,
            calendarSync: calendar.sync,
            // Forgotten with the pairing, like the calendar switches.
            currentWorkspace: currentWorkspace,
            // Switched off and removed with the pairing.
            reminders: reminders
        )
        model.start()
        _appModel = State(initialValue: model)
        let links = ServerLinkModel(
            service: PairingService(server: server, store: store),
            deviceName: { UIDevice.current.name },
            onPaired: { model.didPair($0) }
        )
        _linkModel = State(initialValue: links)
        privacyCover = PrivacyCoverWindow { [model, links] in
            if case .unpaired = model.state { return links.asksForCode }
            return true
        }
        // An upload that gets a 401 sends the user back to pairing, like any other call.
        let shared = AppShared(
            calendar: calendar, currentWorkspace: currentWorkspace, reminders: reminders, reminderRouter: reminderRouter
        )
        environment = AppEnvironment.live(store: store, server: server, shared: shared) { [model] deviceID in
            await model.sessionRevoked(deviceID: deviceID)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(appModel: appModel, environment: environment, linkModel: linkModel)
        }
    }
}
