import Foundation

/// What "Ontkoppelen" does outside the app's own state: telling the server, emptying the upload queue and
/// forgetting the calendar switches. `AppModel.unpair(_:)` runs it; the app builds one from the live server, the
/// upload coordinator and the calendar settings.
public struct Unpairing: Sendable {
    private let server: any BrievieServer
    private let uploads: any UploadQueue
    private let calendarSettings: (any CalendarSettings)?
    private let timeout: Duration

    /// - Parameters:
    ///   - calendarSettings: cleared on unpairing; the calendars themselves stay. Pairing again takes one over by
    ///     its title only when it is in the default calendar source, no other workspace holds it and it has no
    ///     event of the user's own (without a task link) in the window; otherwise a new one is made.
    ///   - timeout: how long the server gets, over all its addresses together, before the app unpairs without it.
    public init(
        server: any BrievieServer, uploads: any UploadQueue, calendarSettings: (any CalendarSettings)? = nil,
        timeout: Duration = .seconds(5)
    ) {
        self.server = server
        self.uploads = uploads
        self.calendarSettings = calendarSettings
        self.timeout = timeout
    }

    /// Scans on this phone that have not reached the server; unpairing deletes them.
    public func queuedScanCount() async -> Int {
        await uploads.items().count
    }

    /// Turns every calendar switch off, stops every upload and deletes every queued scan with its files.
    func wipeLocalState() async throws {
        calendarSettings?.removeAll()
        try await uploads.removeAll()
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
