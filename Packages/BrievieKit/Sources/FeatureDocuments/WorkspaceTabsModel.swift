import BrievieCore
import Foundation
import Observation

/// The navigation of one workspace (navigation design, section 4.5): the tabs Inbox, Mijn post, Taken and Meer in the
/// web's order, starting on "Mijn post"; on an iPad the same places as a sidebar. It also holds the menu's numbers.
/// A new model is made for every workspace shown, so a switch always starts on "Mijn post" again.
@MainActor
@Observable
public final class WorkspaceTabsModel {
    /// The tabs of the iPhone, in this order.
    public enum Tab: Hashable, Sendable, CaseIterable {
        case inbox
        case myPost
        case tasks
        case more
    }

    /// The places of "Meer" (and of the iPad's sidebar below "Mijn taken"), in the web's order.
    public enum Place: Hashable, Sendable {
        case allPost
        case labels
        case label(UUID)
        case trash
        case settings
    }

    /// The iPad's sidebar: the web's menu, top to bottom ("Instellingen" last).
    public enum SidebarItem: Hashable, Sendable {
        case inbox
        case myPost
        case tasks
        case allPost
        case labels
        case trash
        case settings
    }

    /// Whether the server knows "Mijn post" (`getMenuCounts`, host PR #44). Until it answered, "Mijn post" waits:
    /// an older server ignores `addressed_to_me` and would list all post under that name.
    public enum Support: Equatable, Sendable {
        case unknown
        case supported
        case notSupported
    }

    public var selection: Tab = .myPost
    public var sidebarSelection: SidebarItem? = .myPost
    /// What "Meer" has pushed.
    public var morePath: [Place] = []
    /// "Blijft liggen" is pushed on the Inbox.
    public var isShowingLingering = false
    public private(set) var myPostSupport: Support = .unknown
    /// Why the numbers could not be asked while "Mijn post" still waits for them; `nil` otherwise.
    public private(set) var countFailure: String?
    /// The menu's numbers; `nil` before the first answer and from an older server.
    public private(set) var counts: MenuCounts?
    /// The server knows "Mijn taken" (host PR #36). Assumed until a server says otherwise.
    public private(set) var hasTasks = true
    /// The server has a trash (host PR #32); set by the post lists once they found out.
    public var hasTrash = false

    private let documents: WorkspaceDocuments
    private let onRevoked: @MainActor () -> Void
    private let onMissingPairing: @MainActor () -> Void
    /// Opens the search field of "Alle post"; set by the app, which owns that list.
    @ObservationIgnored public var onSearch: @MainActor () -> Void = {}
    /// Whether the server keeps read marks, once known; set by the app, so the lists offer "Gelezen".
    @ObservationIgnored public var onReadingSupport: @MainActor (Bool) -> Void = { _ in }
    /// The number of the latest count: only that one writes `counts`.
    @ObservationIgnored private var latestCount = 0

    public init(
        documents: WorkspaceDocuments, onRevoked: @escaping @MainActor () -> Void,
        onMissingPairing: @escaping @MainActor () -> Void
    ) {
        self.documents = documents
        self.onRevoked = onRevoked
        self.onMissingPairing = onMissingPairing
    }

    /// The tabs to show: "Mijn post" and "Taken" only when the server has them.
    public var tabs: [Tab] {
        Tab.allCases.filter { tab in
            switch tab {
            case .myPost: myPostSupport != .notSupported
            case .tasks: hasTasks
            case .inbox, .more: true
            }
        }
    }

    /// The sidebar's entries above the line and below it, in the web's order.
    public var sidebarItems: [SidebarItem] {
        var items: [SidebarItem] = [.inbox]
        if myPostSupport != .notSupported { items.append(.myPost) }
        if hasTasks { items.append(.tasks) }
        items += [.allPost, .labels]
        if hasTrash { items.append(.trash) }
        return items
    }

    /// Where the app starts and where a workspace switch lands: "Mijn post", or the Inbox on an older server.
    public var startTab: Tab {
        myPostSupport == .notSupported ? .inbox : .myPost
    }

    /// Asks the menu's numbers. The first answer decides whether "Mijn post" exists; any other failure keeps what
    /// is known (and "Mijn post" keeps waiting, with the reason and "Opnieuw proberen").
    public func refreshCounts() async {
        latestCount += 1
        let count = latestCount
        do {
            let fresh = try await documents.menuCounts()
            guard count == latestCount else { return }
            counts = fresh
            countFailure = nil
            if myPostSupport != .supported { onReadingSupport(true) }
            myPostSupport = .supported
            hasTasks = true
        } catch {
            guard count == latestCount else { return }
            await apply(error)
        }
    }

    private func apply(_ error: DocumentsError) async {
        switch error {
        case .notSupported:
            counts = nil
            countFailure = nil
            if myPostSupport != .notSupported { onReadingSupport(false) }
            myPostSupport = .notSupported
            hasTasks = await Self.serverHasTasks(documents)
            if !tabs.contains(selection) { selection = .inbox }
            if let item = sidebarSelection, item != .settings, !sidebarItems.contains(item) {
                sidebarSelection = .inbox
            }
        case .revoked:
            onRevoked()
        case .missingPairing:
            onMissingPairing()
        case .cancelled:
            break
        default:
            countFailure = DocumentsModel.message(for: error)
        }
    }

    /// "Naar Inbox", and the iPad's equivalent.
    public func showInbox() {
        selection = .inbox
        sidebarSelection = .inbox
    }

    /// The "Blijft liggen" card: the Inbox with its letters that lie too long.
    public func showLingering() {
        selection = .inbox
        sidebarSelection = .inbox
        isShowingLingering = true
    }

    public func showTasks() {
        guard hasTasks else { return }
        selection = .tasks
        sidebarSelection = .tasks
    }

    /// "Alle post" from elsewhere (the empty Inbox): the "Meer" tab with "Alle post" open.
    public func showAllPost() {
        selection = .more
        morePath = [.allPost]
        sidebarSelection = .allPost
    }

    /// "Zoeken": "Alle post" with its search field open.
    public func showSearch() {
        showAllPost()
        onSearch()
    }

    /// A tapped reminder: back to the start tab with nothing pushed in "Meer".
    public func showStart() {
        morePath = []
        selection = startTab
        sidebarSelection = startTab == .myPost ? .myPost : .inbox
    }

    /// The badge of a tab: the number that asks for attention, `nil` for none.
    public func badge(for tab: Tab) -> Int? {
        guard let counts else { return nil }
        let number = switch tab {
        case .inbox: counts.inbox
        case .myPost: counts.myPostUnread
        case .tasks: counts.myTasks
        case .more: 0
        }
        return number > 0 ? number : nil
    }

    /// Against a server without menu counts: does it know "Mijn taken"?
    private nonisolated static func serverHasTasks(_ documents: WorkspaceDocuments) async -> Bool {
        do {
            _ = try await documents.myTaskCounts()
            return true
        } catch .notSupported {
            return false
        } catch {
            return true
        }
    }
}
