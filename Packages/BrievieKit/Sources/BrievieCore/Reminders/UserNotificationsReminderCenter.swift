import Foundation
import OSLog
import UserNotifications

/// `ReminderCenter` over the system's `UNUserNotificationCenter`. Local notifications need no entitlement and no
/// server: the system shows them at the planned moment, also when the app is not running.
public struct UserNotificationsReminderCenter: ReminderCenter {
    private static let logger = Logger(subsystem: "nl.stijnvdpol.brievie", category: "reminders")
    /// Groups the reminders in Notification Centre.
    static let threadIdentifier = "deadlines"

    public init() {}

    private var center: UNUserNotificationCenter { .current() }

    public func permission() async -> NotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .allowed
        @unknown default: .denied
        }
    }

    public func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Self.logger.error("Notification permission failed: \(String(describing: error), privacy: .private)")
            return false
        }
    }

    public func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    public func deliveredIdentifiers() async -> [String] {
        await center.deliveredNotifications().map(\.request.identifier)
    }

    public func schedule(_ reminders: [DeadlineReminder]) async {
        for reminder in reminders {
            do {
                try await center.add(Self.request(for: reminder))
            } catch {
                Self.logger.error("A reminder could not be scheduled: \(String(describing: error), privacy: .private)")
            }
        }
    }

    public func removePending(_ identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func removeDelivered(_ identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// The day and time without a time zone: the system rings at 09:00 in whatever zone the phone is in then, also
    /// across a change to or from summer time.
    static func request(for reminder: DeadlineReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.body = reminder.body
        content.sound = .default
        content.threadIdentifier = threadIdentifier
        content.userInfo = ReminderTarget.userInfo(for: reminder)
        let when = DateComponents(
            year: reminder.day.year, month: reminder.day.month, day: reminder.day.day, hour: reminder.hour,
            minute: reminder.minute
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        return UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
    }
}
