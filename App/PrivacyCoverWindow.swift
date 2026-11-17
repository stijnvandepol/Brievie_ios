import BrievieCore
import SwiftUI
import UIKit

/// A window above everything the scene shows (sheets, full-screen covers, the scanner, the photo picker, alerts),
/// up from the moment the scene stops being active until it is active again, so the app switcher's snapshot
/// shows no letter. `PrivacyCoverState` decides; this class only owns the window.
///
/// The scene notifications are observed with no queue, so the cover is up before `willDeactivate` returns, not
/// on a later turn of the run loop.
@MainActor
final class PrivacyCoverWindow {
    private var state = PrivacyCoverState()
    private var window: UIWindow?
    private var observers: [NSObjectProtocol] = []
    private let covers: @MainActor () -> Bool

    private enum Event {
        case willDeactivate
        case didEnterBackground
        case didActivate
    }

    /// - Parameter covers: whether the app's screens may show personal data now (it is paired).
    init(covers: @escaping @MainActor () -> Bool) {
        self.covers = covers
        let events: [(Notification.Name, Event)] = [
            (UIScene.willDeactivateNotification, .willDeactivate),
            (UIScene.didEnterBackgroundNotification, .didEnterBackground),
            (UIScene.didActivateNotification, .didActivate)
        ]
        observers = events.map { name, event in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] note in
                let scene = note.object as? UIWindowScene
                // Scene notifications are posted on the main thread.
                MainActor.assumeIsolated { self?.handle(event, scene: scene) }
            }
        }
    }

    private func handle(_ event: Event, scene: UIWindowScene?) {
        let change = switch event {
        case .willDeactivate: state.sceneWillDeactivate(covers: covers())
        case .didEnterBackground: state.sceneDidEnterBackground(covers: covers())
        case .didActivate: state.sceneDidActivate()
        }
        switch change {
        case .show:
            guard let scene else { return }
            // The keyboard's own window (with its suggestions, which can hold a letter's words) is above any
            // window the app makes: close it, so it is not in the snapshot either.
            for window in scene.windows where window !== self.window { window.endEditing(true) }
            // A new scene (the old one was discarded) gets a new window; a window stays with its own scene.
            let cover = window?.windowScene === scene ? window : nil
            (cover ?? makeWindow(in: scene)).isHidden = false
        case .hide:
            window?.isHidden = true
        case nil:
            break
        }
    }

    private func makeWindow(in scene: UIWindowScene) -> UIWindow {
        let window = UIWindow(windowScene: scene)
        // Above the app's windows and alerts (not above the system keyboard: editing ends before it shows);
        // never made key, so it takes no input from the screens below.
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(rootView: PrivacyCoverView())
        window.accessibilityViewIsModal = true
        self.window = window
        return window
    }
}
