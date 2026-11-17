import Foundation
import Synchronization

/// What "Ontkoppelen" does outside the app's own state: telling the server, emptying the upload queue and
/// forgetting the calendar switches. `AppModel.unpair(_:)` runs it; the app builds one from the live server, the
/// upload coordinator and the calendar settings.
public struct Unpairing: Sendable {
    private let server: any BrievieServer
    private let uploads: any UploadQueue
    private let calendarSettings: (any CalendarSettings)?
    private let calendarSync: CalendarSync?
    private let timeout: Duration
    /// "Ontkoppelen en agenda's verwijderen": each workspace's own calendar goes before the switches are cleared.
    private var removesCalendars = false

    /// - Parameters:
    ///   - calendarSettings: cleared on unpairing; the calendars stay unless `removingCalendars()`. Pairing again takes one over by
    ///     its title only when it is in the default calendar source, no other workspace holds it and it has no
    ///     event of the user's own (without a task link) in the window; otherwise a new one is made.
    ///   - calendarSync: removes the calendars when the user chose `removingCalendars()`.
    ///   - timeout: how long the server gets, over all its addresses together, before the app unpairs without it;
    ///     removing the calendars gets the same time.
    public init(
        server: any BrievieServer, uploads: any UploadQueue, calendarSettings: (any CalendarSettings)? = nil,
        calendarSync: CalendarSync? = nil, timeout: Duration = .seconds(5)
    ) {
        self.server = server
        self.uploads = uploads
        self.calendarSettings = calendarSettings
        self.calendarSync = calendarSync
        self.timeout = timeout
    }

    /// At least one calendar switch is on: the confirmation offers to remove the calendars too.
    public var hasCalendars: Bool {
        !(calendarSettings?.calendarIDs().isEmpty ?? true)
    }

    /// The same unpairing, which also removes each workspace's own calendar.
    public func removingCalendars() -> Unpairing {
        var copy = self
        copy.removesCalendars = true
        return copy
    }

    /// Scans on this phone that have not reached the server; unpairing deletes them.
    public func queuedScanCount() async -> Int {
        await uploads.items().count
    }

    /// Turns every calendar switch off (removing the calendars first when asked), stops every upload and deletes
    /// every queued scan with its files.
    func wipeLocalState() async throws {
        if removesCalendars { await removeCalendars() }
        calendarSettings?.removeAll()
        try await uploads.removeAll()
    }

    /// Best effort and within `timeout`: a calendar that cannot be removed (or a sync that holds it too long)
    /// never stops the user from unpairing. The removal runs in its own task and is only raced against the
    /// timeout, never awaited past it: it may finish later, and then finds the switches cleared and removes or
    /// writes nothing.
    private func removeCalendars() async {
        guard let calendarSync, let calendarSettings else { return }
        let workspaces = Array(calendarSettings.calendarIDs().keys)
        guard !workspaces.isEmpty else { return }
        let timeout = timeout
        // A removal that runs after the wipe (and perhaps a new pairing) must not touch what came since.
        let generation = calendarSettings.clearGeneration()
        let finished = FirstOfTwo()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task.detached {
                for workspace in workspaces {
                    await calendarSync.disable(workspace: workspace, removeCalendar: true, ifGeneration: generation)
                }
                if finished.claim() { continuation.resume() }
            }
            Task.detached {
                try? await Task.sleep(for: timeout)
                if finished.claim() { continuation.resume() }
            }
        }
    }

    /// Best effort: asks the server to revoke this device, trying its addresses in order, within `timeout`.
    /// `true` when the server no longer knows the device afterwards: revoked now, or already gone (401, or
    /// 404 `device_not_found`). Never throws: nothing here may stop the user from unpairing.
    func revokeOnServer(_ connection: ServerConnection, token: String) async -> Bool {
        let server = server
        let timeout = timeout
        return await withTaskGroup(of: Bool?.self) { group in
            group.addTask { await Self.revoke(connection, token: token, on: server) }
            group.addTask {
                // `nil`: the time is up (or this task was cancelled because the server answered).
                try? await Task.sleep(for: timeout)
                return nil
            }
            // The first child to finish decides: an answer from the server, or the timeout (`nil`).
            let first = await group.next().flatMap(\.self)
            group.cancelAll()
            return first ?? false
        }
    }

    private static func revoke(
        _ connection: ServerConnection, token: String, on server: any BrievieServer
    ) async -> Bool {
        let trust = ServerTrust(caCertificateDER: connection.caCertificateDER)
        for url in connection.urls {
            do {
                try await server.revokeDevice(connection.deviceID, at: url, trust: trust, token: token)
                return true
            } catch ServerError.unauthorized, ServerError.other("device_not_found") {
                return true
            } catch ServerError.unreachable, ServerError.untrusted {
                continue
            } catch {
                return false
            }
        }
        return false
    }
}

/// Lets exactly one of two racing tasks resume a continuation.
private final class FirstOfTwo: Sendable {
    private let claimed = Mutex(false)

    /// `true` for the first caller only.
    func claim() -> Bool {
        claimed.withLock { claimed in
            defer { claimed = true }
            return !claimed
        }
    }
}
