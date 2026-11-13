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
    private let launchFlag: any LaunchFlag
    private var isAuthenticating = false
    private var wentToBackgroundWhileAuthenticating = false
    /// Prompt automatically on the next activation: at launch and after every trip to the background, but not
    /// when the system's own prompt closes (that also makes the scene active again).
    private var promptsOnActivation = true
    /// Set between `didEnterBackground()` and `didBecomeActive()`. A pairing that completes in that window
    /// must not open the app: nobody is looking at it.
    private var isInBackground = false
    /// The task started by `requestUnlock()` or `sceneActivated()`; tests await it.
    @ObservationIgnored private(set) var pendingTask: Task<Void, Never>?

    public init(store: ConnectionStore, authenticator: any DeviceAuthenticator, launchFlag: any LaunchFlag) {
        self.store = store
        self.authenticator = authenticator
        self.launchFlag = launchFlag
    }

    /// Unpaired when nothing is stored, locked otherwise. A store that cannot be read does not unpair the
    /// user (that would invite pairing over a valid pairing): the app stays locked and `unlock()` reads again.
    ///
    /// The first start after an install clears the store first: Keychain items outlive the app, and a
    /// pairing left behind by a previous install must not open the new one.
    public func start() {
        promptsOnActivation = true
        clearLeftoversOfAPreviousInstall()
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

        switch authenticator.availability() {
        case .noPasscode:
            showsNoPasscodeWarning = true
            finishUnlock()
            return
        case .unavailable:
            // Not "no passcode": stay locked, the unlock button tries again.
            showsNoPasscodeWarning = false
            return
        case .available:
            showsNoPasscodeWarning = false
        }
        let succeeded = await authenticator.authenticate(reason: AppStrings.lockReason)
        // An unlock that finished after the app went to the background must not leave it open.
        guard succeeded, !wentToBackgroundWhileAuthenticating else { return }
        finishUnlock()
    }

    /// The scene became active. Prompts once per launch or return from the background.
    public func didBecomeActive() async {
        isInBackground = false
        guard promptsOnActivation, state == .locked else { return }
        promptsOnActivation = false
        await unlock()
    }

    /// A pairing that completes while the app is in the background leaves it locked: the user unlocks on return.
    public func didPair(_ connection: ServerConnection) {
        showsNoPasscodeWarning = authenticator.availability() == .noPasscode
        state = isInBackground ? .locked : .ready(connection)
    }

    /// The scene went to the background (not merely inactive: Face ID's own sheet makes the scene inactive).
    public func didEnterBackground() {
        isInBackground = true
        promptsOnActivation = true
        wentToBackgroundWhileAuthenticating = isAuthenticating
        if case .ready = state { state = .locked }
    }

    /// The server answered 401 for the device `deviceID`: forget the pairing and send the user back to pairing.
    /// A screen from an older connection may report late; it only counts when `deviceID` is the stored
    /// connection's, so it cannot wipe a pairing made since.
    public func sessionRevoked(deviceID: UUID) {
        do {
            if let stored = try store.load(), stored.connection.deviceID != deviceID { return }
        } catch {
            return
        }
        // If the Keychain refuses to delete, the next launch finds the same token, gets another 401 and ends up here again.
        try? store.clear()
        state = .unpaired(notice: AppStrings.sessionRevoked)
    }

    /// The stored pairing is gone although the app thinks it is paired. Not a revocation by the server, so the
    /// notice is the generic one.
    public func connectionMissing() {
        state = .unpaired(notice: AppStrings.genericError)
    }

    /// For views: unlocks without tying the work to the lifetime of a screen.
    public func requestUnlock() {
        pendingTask = Task { await unlock() }
    }

    /// For views: the scene became active. The model owns the task; a screen going away must not cancel it.
    public func sceneActivated() {
        pendingTask = Task { await didBecomeActive() }
    }

    private func finishUnlock() {
        do {
            guard let paired = try store.load() else {
                connectionMissing()
                return
            }
            state = .ready(paired.connection)
        } catch {
            // Consistent with `start()`: an unreadable store is not an unpaired one.
            state = .locked
        }
    }

    private func clearLeftoversOfAPreviousInstall() {
        guard !launchFlag.hasLaunchedBefore else { return }
        do {
            try store.clear()
            launchFlag.markLaunched()
        } catch {
            // Try again next launch; meanwhile the normal load decides.
        }
    }
}
