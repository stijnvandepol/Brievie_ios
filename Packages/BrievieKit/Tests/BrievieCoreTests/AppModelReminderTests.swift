@testable import BrievieCore
import Foundation
import Testing

/// Forgetting the pairing ("Ontkoppelen" or a revocation by the server) switches reminders off and removes every
/// reminder, pending and shown: they are about this pairing's tasks.
@MainActor
@Suite struct AppModelReminderTests {
    private let secrets = InMemorySecretStore()
    private var store: ConnectionStore { ConnectionStore(secrets: secrets) }
    private let server: FakeBrievieServer
    private let connection: ServerConnection
    private let center = InMemoryReminderCenter()
    private let settings = InMemoryReminderSettings()
    private let workspace = UUID()

    init() throws {
        server = try FakeBrievieServer()
        let url = try #require(URL(string: "https://brievie.local"))
        connection = ServerConnection(urls: [url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn")
        try ConnectionStore(secrets: secrets).save(connection, token: "device-token")
    }

    /// Reminders on, with one task's two reminders pending and one of them already shown.
    private func remindersOn() async -> DeadlineReminders {
        settings.setEnabled(true)
        let task = WorkspaceTask(
            id: UUID(), type: "pay", description: "Factuur", deadline: CalendarDate(year: 2026, month: 12, day: 10),
            isDone: false, documentID: nil, sender: "Eneco"
        )
        let reminders = DeadlineReminders(
            center: center, settings: settings, tasks: { _ in [task] },
            now: { Date(timeIntervalSince1970: 1_795_086_000) },
            timeZone: { TimeZone(identifier: "Europe/Amsterdam") ?? .gmt }
        )
        await reminders.reschedule(workspaces: [workspace])
        center.deliver(ReminderPlanner.identifier(workspace: workspace, task: task.id, kind: .ahead))
        #expect(center.pending.count == 1)
        #expect(center.delivered.count == 1)
        return reminders
    }

    private func readyModel(reminders: DeadlineReminders) async -> AppModel {
        let model = AppModel(
            store: store, authenticator: FakeAuthenticator(), launchFlag: InMemoryLaunchFlag(hasLaunchedBefore: true),
            isProtectedDataAvailable: { true }, reminders: reminders
        )
        model.start()
        await model.unlock()
        return model
    }

    @Test func unpairingRemovesEveryReminderAndSwitchesThemOff() async throws {
        let reminders = await remindersOn()
        let model = await readyModel(reminders: reminders)

        let unpaired = await model.unpair(Unpairing(server: server, uploads: EmptyUploadQueue()))
        await model.reminderRemovalTask?.value

        #expect(unpaired)
        #expect(!settings.isEnabled())
        #expect(center.pending.isEmpty)
        #expect(center.delivered.isEmpty)
    }

    @Test func aRevocationRemovesEveryReminderAndSwitchesThemOff() async throws {
        let reminders = await remindersOn()
        let model = await readyModel(reminders: reminders)

        model.sessionRevoked(deviceID: connection.deviceID)
        // Off at once, in the same turn as the pairing screen.
        #expect(!settings.isEnabled())
        await model.reminderRemovalTask?.value

        #expect(model.state == .unpaired(notice: AppStrings.sessionRevoked))
        #expect(center.pending.isEmpty)
        #expect(center.delivered.isEmpty)
    }

    @Test func pairingAgainBringsNothingBack() async throws {
        let reminders = await remindersOn()
        let model = await readyModel(reminders: reminders)
        model.sessionRevoked(deviceID: connection.deviceID)
        await model.reminderRemovalTask?.value

        // A refresh queued before the new pairing loaded its workspaces knows none of the old ones.
        settings.setEnabled(true)
        await reminders.reschedule()

        #expect(center.pending.isEmpty)
    }
}
