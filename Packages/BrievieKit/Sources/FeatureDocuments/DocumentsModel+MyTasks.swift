import BrievieCore
import Foundation

// "Mijn taken" next to the Inbox: its counts, the link row on top of the Inbox, and making the screen of the
// "Taken" tab. A thin adapter: the screen itself is `MyTasksModel`.
extension DocumentsModel {
    /// The row on top of the Inbox that opens "Mijn taken".
    public struct MyTasksLink: Equatable, Sendable {
        public let text: String
        /// Something is overdue: the warning colour and symbol, and the words in `text`.
        public let isLate: Bool
    }

    /// What `countMyTasks` said on a whole load.
    enum MyTaskCountsAnswer: Sendable {
        case counts(MyTaskCounts)
        case notSupported
        /// Unreachable or another failure: what is known stays.
        case unknown
    }

    nonisolated static func fetchMyTaskCounts(_ documents: WorkspaceDocuments) async -> MyTaskCountsAnswer {
        do {
            return .counts(try await documents.myTaskCounts())
        } catch .notSupported {
            return .notSupported
        } catch {
            return .unknown
        }
    }

    func apply(_ answer: MyTaskCountsAnswer) {
        switch answer {
        case let .counts(counts):
            myTaskCounts = counts
            hasMyTasks = true
        case .notSupported:
            myTaskCounts = nil
            hasMyTasks = false
        case .unknown:
            break
        }
    }

    /// "Mijn taken: 4 open, waarvan 1 te laat" on top of the Inbox; `nil` without open tasks or counts.
    public var myTasksLink: MyTasksLink? {
        guard scope == .inbox, let counts = myTaskCounts, counts.mine > 0 else { return nil }
        if counts.overdue > 0 {
            return MyTasksLink(
                text: String(format: DocumentStrings.myTasksLinkCountLateFormat, counts.mine, counts.overdue),
                isLate: true
            )
        }
        return MyTasksLink(text: String(format: DocumentStrings.myTasksLinkCountFormat, counts.mine), isLate: false)
    }

    /// The "Mijn taken" screen of this workspace. A change there lets the calendar and reminders follow and
    /// counts again.
    /// - Parameter showInbox: "Naar Inbox" under the waiting letters (the Inbox tab).
    public func makeMyTasksModel(showInbox: @escaping @MainActor () -> Void) -> MyTasksModel {
        MyTasksModel(
            documents: documents, canEdit: canScan, locale: locale,
            onTasksChanged: { [weak self] in
                guard let self else { return }
                onTasksChanged()
                Task { await self.refreshMyTaskCounts() }
            },
            onShowInbox: showInbox,
            onRevoked: onRevoked, onMissingPairing: onMissingPairing
        )
    }

    /// Counts again (after a change in "Mijn taken").
    public func refreshMyTaskCounts() async {
        apply(await Self.fetchMyTaskCounts(documents))
    }
}
