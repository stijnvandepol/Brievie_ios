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
    /// "Ontkoppelen" is running (telling the server takes up to a few seconds); the button waits for it.
    public private(set) var isUnpairing = false

    private let store: ConnectionStore
    private let authenticator: any DeviceAuthenticator
    private let launchFlag: any LaunchFlag
    private let isProtectedDataAvailable: @MainActor () -> Bool
    /// Cleared with the pairing (revoked or unpaired), so the switches do not come back on after pairing again.
    private let calendarSettings: (any CalendarSettings)?
    /// Removes the calendars after a revocation by the server.
    private let calendarSync: CalendarSync?
    /// The first-launch check has completed (or a pairing made it moot) in this process. Until then nothing
    /// unlocks: a stored connection may be a leftover of a previous install.
    private var launchCheckDone = false
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
    /// The task started by `requestUnpair(_:)`; owned by the model, so the screen going away cannot cancel it.
    @ObservationIgnored private(set) var unpairTask: Task<Void, Never>?
    /// The removal of the calendars after a revocation; tests await it.
    @ObservationIgnored private(set) var calendarRemovalTask: Task<Void, Never>?

    /// A pairing that must be forgotten but is not yet: emptying the queue or clearing the store failed.
    /// Until it succeeds the app stays locked (never "unpaired" with a token left in the Keychain) and every
    /// activation and unlock attempt tries again.
    private struct PendingForget {
        let notice: String?
        /// Unpairing only; `nil` once the queue is empty.
        var wipeUploads: (@Sendable () async throws -> Void)?
        /// A revocation: the calendars go too, without asking (unpairing asks, and removes them itself).
        var removesCalendars = false
    }

    @ObservationIgnored private var pendingForget: PendingForget?

    /// - Parameter isProtectedDataAvailable: `false` before the first unlock after a reboot (prewarm or
    ///   background launch), when the Keychain and `UserDefaults` may not be readable yet.
    /// - Parameter calendarSettings: the calendar switches, cleared whenever the pairing is forgotten.
    /// - Parameter calendarSync: removes the calendars those switches named when the server revoked the device;
    ///   on "Ontkoppelen" the user chooses (`Unpairing`).
    public init(
        store: ConnectionStore,
        authenticator: any DeviceAuthenticator,
        launchFlag: any LaunchFlag,
        isProtectedDataAvailable: @escaping @MainActor () -> Bool,
        calendarSettings: (any CalendarSettings)? = nil,
        calendarSync: CalendarSync? = nil
    ) {
        self.store = store
        self.authenticator = authenticator
        self.launchFlag = launchFlag
        self.isProtectedDataAvailable = isProtectedDataAvailable
        self.calendarSettings = calendarSettings
        self.calendarSync = calendarSync
    }

    /// Unpaired when nothing is stored, locked otherwise. A store that cannot be read does not unpair the
    /// user (that would invite pairing over a valid pairing): the app stays locked and `unlock()` reads again.
    ///
    /// Never clears anything: this runs from `App.init`, possibly before the device was unlocked. The
    /// first-launch clear waits for the first activation (see `didBecomeActive()`).
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
    ///
    /// Gated by the first-launch check: while it has not completed, the app stays locked.
    public func unlock() async {
        clearLeftoversOfAPreviousInstall()
        guard await finishForgetting() else { return }
        guard launchCheckDone, state == .locked, !isAuthenticating else { return }
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
        await activate()
    }

    private func activate() async {
        // The scene may have gone to the background again before this ran.
        guard !isInBackground else { return }
        // `UserDefaults` may not be readable before the first unlock after a reboot.
        if isProtectedDataAvailable() { removePendingCalendars() }
        clearLeftoversOfAPreviousInstall()
        guard await finishForgetting() else { return }
        // A pending check keeps the prompt for the activation that completes it.
        guard launchCheckDone, promptsOnActivation, state == .locked else { return }
        promptsOnActivation = false
        await unlock()
    }

    /// A pairing that completes while the app is in the background leaves it locked: the user unlocks on return.
    public func didPair(_ connection: ServerConnection) {
        // A pairing made now must never be taken for a leftover of an earlier install.
        launchFlag.markLaunched()
        launchCheckDone = true
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
        // The user is unpairing: a 401 is the expected result of that, and the unpair forgets the pairing itself.
        guard !isUnpairing else { return }
        do {
            if let stored = try store.load(), stored.connection.deviceID != deviceID { return }
        } catch {
            return
        }
        // An unpair whose queue could not be emptied yet keeps that step.
        // A pending "Ontkoppelen" keeps its own choice about the calendars (it removes them itself when chosen).
        pendingForget = PendingForget(
            notice: AppStrings.sessionRevoked, wipeUploads: pendingForget?.wipeUploads,
            removesCalendars: pendingForget?.removesCalendars ?? true
        )
        if pendingForget?.wipeUploads == nil {
            clearForgottenPairing()
        } else {
            state = .locked
        }
    }

    /// For the "Ontkoppelen" button: unpairs without tying the work to the lifetime of a screen. Safe against
    /// a double tap; does nothing unless the app is open.
    public func requestUnpair(_ unpairing: Unpairing) {
        guard case .ready = state, !isUnpairing else { return }
        isUnpairing = true
        unpairTask = Task {
            await performUnpair(unpairing)
            isUnpairing = false
        }
    }

    /// "Ontkoppelen": tells the server (best effort, see `Unpairing.revokeOnServer`), empties the upload queue
    /// and forgets the pairing, then shows pairing; with a notice when the server could not be told.
    /// Only from the open app, and only once at a time. `true` when the app ended unpaired; `false` when it
    /// did not run, or when emptying the queue or clearing the store failed (the app then stays locked and
    /// retries, like the revoked path).
    @discardableResult
    public func unpair(_ unpairing: Unpairing) async -> Bool {
        guard case .ready = state, !isUnpairing else { return false }
        isUnpairing = true
        defer { isUnpairing = false }
        return await performUnpair(unpairing)
    }

    @discardableResult
    private func performUnpair(_ unpairing: Unpairing) async -> Bool {
        var serverTold = false
        if let stored = try? store.load() {
            serverTold = await unpairing.revokeOnServer(stored.connection, token: stored.token)
        }
        pendingForget = PendingForget(
            notice: serverTold ? nil : AppStrings.serverStillKnowsDevice,
            wipeUploads: { try await unpairing.wipeLocalState() }
        )
        return await finishForgetting()
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
        // Synchronously, so that a background callback in the same turn wins; the task re-checks it.
        isInBackground = false
        pendingTask = Task { await activate() }
    }

    /// For the app: the device was unlocked for the first time since a reboot, so a first-launch check that
    /// had to wait can run now. Acts as an activation when the scene is in the foreground.
    public func protectedDataDidBecomeAvailable() {
        guard !isInBackground else { return }
        pendingTask = Task { await activate() }
    }

    /// Completes a pending forget (revoked or unpaired): empties the queue if that is still to do, then clears
    /// the store and shows pairing. On failure the app stays locked; `true` when nothing is pending any more.
    /// The one path both `sessionRevoked(deviceID:)` and `unpair(_:)` end in.
    private func finishForgetting() async -> Bool {
        guard let pending = pendingForget else { return true }
        if let wipeUploads = pending.wipeUploads {
            do {
                try await wipeUploads()
            } catch {
                state = .locked
                return false
            }
            // Another attempt may have finished meanwhile; then there is nothing left to do.
            guard pendingForget != nil else { return true }
            pendingForget?.wipeUploads = nil
        }
        return clearForgottenPairing()
    }

    /// The store part of a pending forget; synchronous, so a 401 shows pairing in the same turn.
    @discardableResult
    private func clearForgottenPairing() -> Bool {
        guard let pending = pendingForget else { return true }
        do {
            try store.clear()
        } catch {
            state = .locked
            return false
        }
        if pending.removesCalendars, let calendarSettings {
            // Stored before the switches are cleared, apart from them: a removal that cannot run now (no calendar
            // access, the app ended) is tried again on every activation.
            let calendars = calendarSettings.calendarIDs().map { ($0.value, $0.key) }
            calendarSettings.markForRemoval(Dictionary(calendars, uniquingKeysWith: { first, _ in first }))
        }
        calendarSettings?.removeAll()
        pendingForget = nil
        state = .unpaired(notice: pending.notice)
        removePendingCalendars()
        return true
    }

    /// Removes the calendars still marked after a revocation, after any removal already running.
    private func removePendingCalendars() {
        guard let calendarSync, let calendarSettings, !calendarSettings.pendingRemovals().isEmpty else { return }
        let previous = calendarRemovalTask
        calendarRemovalTask = Task {
            await previous?.value
            await calendarSync.removePendingRemovals()
        }
    }

    private func finishUnlock() {
        guard launchCheckDone, pendingForget == nil else { return }
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

    /// On the first activation after an install, clears the store: Keychain items outlive the app, and a pairing
    /// left behind by a previous install must not open the new one. Completes at most once per process, and not
    /// while protected data is unavailable (the flag would read `false` for a device that was merely not unlocked
    /// yet). Until it completes, `unlock()` does nothing; every activation and unlock attempt retries it.
    private func clearLeftoversOfAPreviousInstall() {
        guard !launchCheckDone, isProtectedDataAvailable() else { return }
        if launchFlag.hasLaunchedBefore {
            launchCheckDone = true
            return
        }
        do {
            try store.clear()
            launchFlag.markLaunched()
            launchCheckDone = true
            state = .unpaired(notice: nil)
        } catch {
            // Stay locked; the next activation or unlock attempt tries again.
        }
    }
}
