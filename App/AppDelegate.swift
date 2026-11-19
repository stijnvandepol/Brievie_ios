import BrievieCore
import UIKit
import UserNotifications

/// Receives the system's wake-up when background uploads finished while the app was not running, and the tap on a
/// deadline reminder.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by `AppEnvironment.live` at launch, before the system can call back.
    static var uploads: UploadCoordinator?
    /// Set by `BrievieApp` at launch: a tapped reminder waits here until the paired app shows it.
    static var reminderRouter: ReminderRouter?
    /// The system's completion handlers, oldest first: each is called once its events are reflected in the
    /// queue. More than one when the system wakes the app again before the first events were handled.
    private static var backgroundEventsCompletions: [() -> Void] = []

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Before launching ends, so a tap that launched the app is delivered here.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundUploadTransport.sessionIdentifier, let uploads = Self.uploads else {
            completionHandler()
            return
        }
        Self.backgroundEventsCompletions.append(completionHandler)
        // The coordinator calls this exactly once, on the main actor, also when the events were handled
        // before this task ran.
        Task { await uploads.setEventsHandler { Self.finishBackgroundEvents() } }
    }

    /// A tapped reminder opens the app (behind the lock, as always) and then its letter. Only ids are read.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let target = ReminderTarget(userInfo: response.notification.request.content.userInfo)
        else { return }
        await MainActor.run { Self.reminderRouter?.open(target) }
    }

    /// A reminder that goes off while Brievie is open shows as a banner too.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    private static func finishBackgroundEvents() {
        guard !backgroundEventsCompletions.isEmpty else { return }
        backgroundEventsCompletions.removeFirst()()
    }
}
