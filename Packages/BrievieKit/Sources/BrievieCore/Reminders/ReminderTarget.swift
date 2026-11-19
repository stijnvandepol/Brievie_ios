import Foundation
import Observation

/// Where a tapped reminder leads: the workspace, and the letter of the task when it has one.
public struct ReminderTarget: Equatable, Sendable {
    public let workspaceID: UUID
    public let documentID: UUID?

    public init(workspaceID: UUID, documentID: UUID?) {
        self.workspaceID = workspaceID
        self.documentID = documentID
    }

    private static let workspaceKey = "workspace"
    private static let documentKey = "document"

    /// Stored with the notification on the phone (ids only, never shown).
    public static func userInfo(for reminder: DeadlineReminder) -> [String: String] {
        var info = [workspaceKey: reminder.workspaceID.uuidString]
        if let document = reminder.documentID { info[documentKey] = document.uuidString }
        return info
    }

    /// The target of a tapped notification; `nil` for anything that is not one of Brievie's reminders.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let text = userInfo[Self.workspaceKey] as? String, let workspace = UUID(uuidString: text) else {
            return nil
        }
        workspaceID = workspace
        documentID = (userInfo[Self.documentKey] as? String).flatMap(UUID.init(uuidString:))
    }
}

/// The reminder the user tapped, until the paired app has shown it. Set by the app delegate (possibly before the
/// app is unlocked); the paired screens take it once the app is open.
@MainActor
@Observable
public final class ReminderRouter {
    public private(set) var target: ReminderTarget?

    public init() {}

    public func open(_ target: ReminderTarget) {
        self.target = target
    }

    /// The letter part is done (shown, or there is none): nothing is left to open.
    public func finish() {
        target = nil
    }
}
