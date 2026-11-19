import Foundation
import Synchronization

/// Whether the system lets Brievie show notifications.
public enum NotificationPermission: Equatable, Sendable {
    /// Never asked: switching reminders on asks.
    case notDetermined
    /// Refused, in the prompt or later in Settings.
    case denied
    /// Allowed (also provisionally).
    case allowed
}

/// The part of the system's notification centre the reminders use. The live one is `UNUserNotificationCenter`
/// (`UserNotificationsReminderCenter`); tests use `InMemoryReminderCenter`.
public protocol ReminderCenter: Sendable {
    func permission() async -> NotificationPermission
    /// Shows the system's question; `true` when allowed.
    func requestPermission() async -> Bool
    /// Identifiers of every pending notification of the app.
    func pendingIdentifiers() async -> [String]
    /// Identifiers of every delivered notification still in Notification Centre.
    func deliveredIdentifiers() async -> [String]
    /// Adds the reminders; one with an identifier that is pending already replaces it.
    func schedule(_ reminders: [DeadlineReminder]) async
    func removePending(_ identifiers: [String]) async
    func removeDelivered(_ identifiers: [String]) async
}

/// `ReminderCenter` in memory, for tests and previews: it keeps what is pending and delivered, never shows anything.
public final class InMemoryReminderCenter: ReminderCenter {
    private struct State {
        var permission: NotificationPermission
        var answer: Bool
        var pending: [String: DeadlineReminder] = [:]
        var delivered: Set<String> = []
        var requests = 0
    }

    private let state: Mutex<State>

    /// - Parameters:
    ///   - permission: what the system says now.
    ///   - answer: what the user answers when asked.
    public init(permission: NotificationPermission = .allowed, answer: Bool = true) {
        state = Mutex(State(permission: permission, answer: answer))
    }

    /// What is pending, by identifier.
    public var pending: [String: DeadlineReminder] { state.withLock { $0.pending } }
    public var delivered: Set<String> { state.withLock { $0.delivered } }
    /// How often the system's question was shown.
    public var permissionRequests: Int { state.withLock { $0.requests } }

    public func setPermission(_ permission: NotificationPermission) {
        state.withLock { $0.permission = permission }
    }

    /// The system shows a pending reminder: it moves to Notification Centre.
    public func deliver(_ identifier: String) {
        state.withLock { state in
            if state.pending.removeValue(forKey: identifier) != nil { state.delivered.insert(identifier) }
        }
    }

    /// A notification of the app that is not a reminder (none exist today; this checks they would be left alone).
    public func addForeign(_ identifier: String) {
        _ = state.withLock { $0.delivered.insert(identifier) }
    }

    public func permission() async -> NotificationPermission {
        state.withLock { $0.permission }
    }

    public func requestPermission() async -> Bool {
        state.withLock { state in
            state.requests += 1
            guard state.permission == .notDetermined else { return state.permission == .allowed }
            state.permission = state.answer ? .allowed : .denied
            return state.answer
        }
    }

    public func pendingIdentifiers() async -> [String] {
        state.withLock { Array($0.pending.keys) }
    }

    public func deliveredIdentifiers() async -> [String] {
        state.withLock { Array($0.delivered) }
    }

    public func schedule(_ reminders: [DeadlineReminder]) async {
        state.withLock { state in
            for reminder in reminders { state.pending[reminder.identifier] = reminder }
        }
    }

    public func removePending(_ identifiers: [String]) async {
        state.withLock { state in
            for identifier in identifiers { state.pending[identifier] = nil }
        }
    }

    public func removeDelivered(_ identifiers: [String]) async {
        state.withLock { state in
            for identifier in identifiers { state.delivered.remove(identifier) }
        }
    }
}
