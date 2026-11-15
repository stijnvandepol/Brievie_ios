import BrievieCore
import UIKit

/// Receives the system's wake-up when background uploads finished while the app was not running.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set by `AppEnvironment.live` at launch, before the system can call back.
    static var uploads: UploadCoordinator?
    /// The system's completion handlers, oldest first: each is called once its events are reflected in the
    /// queue. More than one when the system wakes the app again before the first events were handled.
    private static var backgroundEventsCompletions: [() -> Void] = []

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

    private static func finishBackgroundEvents() {
        guard !backgroundEventsCompletions.isEmpty else { return }
        backgroundEventsCompletions.removeFirst()()
    }
}
