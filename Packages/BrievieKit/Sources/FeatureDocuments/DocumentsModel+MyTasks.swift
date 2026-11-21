import BrievieCore
import Foundation

// "Mijn taken" next to the Inbox: the entry in the title menu with its count, a link row on top of the Inbox, and
// switching between the post list and the tasks. A thin adapter: the screen itself is `MyTasksModel`, which a
// "Taken" tab can own later without this file.
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
            isShowingMyTasks = false
        case .unknown:
            break
        }
    }

    /// The menu entry: "Mijn taken · 4 open, 1 te laat" (a menu shows no colour, so the words carry it).
    public var myTasksMenuTitle: String {
        guard let counts = myTaskCounts, counts.mine > 0 else { return DocumentStrings.myTasksTitle }
        if counts.overdue > 0 {
            return String(format: DocumentStrings.myTasksMenuCountLateFormat, counts.mine, counts.overdue)
        }
        return String(format: DocumentStrings.myTasksMenuCountFormat, counts.mine)
    }

    /// "Mijn taken: 4 open, waarvan 1 te laat" on top of the Inbox; `nil` without open tasks or counts.
    public var myTasksLink: MyTasksLink? {
        guard scope == .inbox, !isShowingMyTasks, let counts = myTaskCounts, counts.mine > 0 else { return nil }
        if counts.overdue > 0 {
            return MyTasksLink(
                text: String(format: DocumentStrings.myTasksLinkCountLateFormat, counts.mine, counts.overdue),
                isLate: true
            )
        }
        return MyTasksLink(text: String(format: DocumentStrings.myTasksLinkCountFormat, counts.mine), isLate: false)
    }

    /// The title of what the screen shows: "Mijn taken", or the scope.
    public var screenTitle: String {
        isShowingMyTasks ? DocumentStrings.myTasksTitle : scopeTitle
    }

    public func showMyTasks() {
        guard hasMyTasks else { return }
        undo = nil
        duplicateNotice = nil
        isShowingMyTasks = true
    }

    /// "Naar Inbox" in "Mijn taken".
    public func showInbox() async {
        await select(.inbox)
    }

    /// The "Mijn taken" screen of this workspace. A change there lets the calendar and reminders follow and
    /// counts again.
    public func makeMyTasksModel() -> MyTasksModel {
        MyTasksModel(
            documents: documents, canEdit: canScan, locale: locale,
            onTasksChanged: { [weak self] in
                guard let self else { return }
                onTasksChanged()
                Task { await self.refreshMyTaskCounts() }
            },
            onShowInbox: { [weak self] in
                guard let self else { return }
                Task { await self.showInbox() }
            },
            onRevoked: onRevoked, onMissingPairing: onMissingPairing
        )
    }

    /// Counts again (after a change in "Mijn taken").
    public func refreshMyTaskCounts() async {
        apply(await Self.fetchMyTaskCounts(documents))
    }
}
