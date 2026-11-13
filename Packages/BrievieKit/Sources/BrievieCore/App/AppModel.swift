import Foundation
import Observation

/// What the app shows: pairing, the lock screen, or the paired app. The single source of truth for the root view.
@MainActor
@Observable
public final class AppModel {
    public enum State: Equatable {
        /// Not paired. `notice` explains why the user is here, for example after the server revoked the device.
        case unpaired(notice: String?)
        case locked
        case ready(ServerConnection)
    }

    public private(set) var state: State = .unpaired(notice: nil)
    /// `true` when the device has no passcode, so the app cannot lock itself. The app opens with a warning
    /// instead of locking the user out.
    public private(set) var showsNoPasscodeWarning = false

    private let store: ConnectionStore
    private let authenticator: any DeviceAuthenticator
    private var isAuthenticating = false
    private var wentToBackgroundWhileAuthenticating = false
    /// Prompt automatically on the next activation: at launch and after every trip to the background, but not
    /// when the system's own prompt closes (that also makes the scene active again).
    private var promptsOnActivation = true

    public init(store: ConnectionStore, authenticator: any DeviceAuthenticator) {
        self.store = store
        self.authenticator = authenticator
    }

    /// Unpaired when nothing is stored, locked otherwise. A store that cannot be read does not unpair the
    /// user (that would invite pairing over a valid pairing): the app stays locked and `unlock()` reads again.
    public func start() {
        promptsOnActivation = true
        do {
            state = try store.load() == nil ? .unpaired(notice: nil) : .locked
        } catch {
            state = .locked
        }
    }

    /// Asks for Face ID or the passcode; `.locked` becomes `.ready` on success. Without a passcode there is
    /// nothing to ask: the app opens and `showsNoPasscodeWarning` is set.
    public func unlock() async {
        guard state == .locked, !isAuthenticating else { return }
        isAuthenticating = true
        wentToBackgroundWhileAuthenticating = false
        defer { isAuthenticating = false }

        guard authenticator.canAuthenticate() else {
            showsNoPasscodeWarning = true
            finishUnlock()
            return
        }
        showsNoPasscodeWarning = false
        let succeeded = await authenticator.authenticate(reason: AppStrings.lockReason)
        // An unlock that finished after the app went to the background must not leave it open.
        guard succeeded, !wentToBackgroundWhileAuthenticating else { return }
        finishUnlock()
    }

    /// The scene became active. Prompts once per launch or return from the background.
    public func didBecomeActive() async {
        guard promptsOnActivation, state == .locked else { return }
        promptsOnActivation = false
        await unlock()
    }

    public func didPair(_ connection: ServerConnection) {
        showsNoPasscodeWarning = !authenticator.canAuthenticate()
        state = .ready(connection)
    }

    /// The scene went to the background (not merely inactive: Face ID's own sheet makes the scene inactive).
    public func didEnterBackground() {
        promptsOnActivation = true
        wentToBackgroundWhileAuthenticating = isAuthenticating
        if case .ready = state { state = .locked }
    }

    /// The server answered 401: forget the pairing and send the user back to pairing.
    public func sessionRevoked() {
        // If the Keychain refuses to delete, the next launch finds the same token, gets another 401 and ends up here again.
        try? store.clear()
        state = .unpaired(notice: AppStrings.sessionRevoked)
    }

    private func finishUnlock() {
        do {
            guard let paired = try store.load() else {
                state = .unpaired(notice: nil)
                return
            }
            state = .ready(paired.connection)
        } catch {
            state = .unpaired(notice: AppStrings.genericError)
        }
    }
}
