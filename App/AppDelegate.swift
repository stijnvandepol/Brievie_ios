import BrievieCore
import UIKit

/// Receives the system's wake-up when background uploads finished while the app was not running.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set by `AppEnvironment.live` at launch, before the system can call back.
    static var uploads: UploadCoordinator?
    /// The system's completion handler: called once the queue reflects every delivered event.
    private static var backgroundEventsCompletion: (() -> Void)?

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundUploadTransport.sessionIdentifier, let uploads = Self.uploads else {
            completionHandler()
            return
        }
        Self.backgroundEventsCompletion = completionHandler
        Task { await uploads.setEventsHandler { Self.finishBackgroundEvents() } }
    }

    private static func finishBackgroundEvents() {
        backgroundEventsCompletion?()
        backgroundEventsCompletion = nil
    }
}
