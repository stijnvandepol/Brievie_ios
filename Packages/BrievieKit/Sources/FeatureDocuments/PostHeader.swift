#if os(iOS)
import BrievieUI
import SwiftUI

/// What stands above a post list on a tab root: the count cards and the round quick actions (navigation design,
/// section 10), and a notice when the list cannot have letters yet.
public struct PostHeader {
    public enum Action: Hashable, Sendable {
        case scan
        case search
        case allRead
        case chooseName
    }

    public var cards: [WorkspaceTabsModel.Card]
    /// The round buttons in order; a button whose action has nothing to do is shown disabled.
    public var actions: [Action]
    public var disabled: Set<Action>
    public var notice: String?
    public var openCard: (CountCardKind) -> Void
    /// Every action but `.scan`, which the list's own scan button handles.
    public var perform: (Action) -> Void

    public init(
        cards: [WorkspaceTabsModel.Card], actions: [Action], disabled: Set<Action> = [], notice: String? = nil,
        openCard: @escaping (CountCardKind) -> Void, perform: @escaping (Action) -> Void
    ) {
        self.cards = cards
        self.actions = actions
        self.disabled = disabled
        self.notice = notice
        self.openCard = openCard
        self.perform = perform
    }

    var isEmpty: Bool { cards.isEmpty && actions.isEmpty && notice == nil }
}

/// The rendering of a `PostHeader`, as the first section of the list, on the list's background.
struct PostHeaderSection: View {
    let header: PostHeader
    let scan: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 20) {
                if !header.cards.isEmpty {
                    CountCardRow {
                        ForEach(header.cards) { card in
                            CountCard(
                                number: card.number, caption: card.caption, detail: card.detail,
                                detailIsWarning: card.detailIsWarning, accessibilityLabel: card.accessibilityLabel,
                                action: { header.openCard(card.kind) }
                            )
                        }
                    }
                }
                if !header.actions.isEmpty {
                    RoundActionBar {
                        ForEach(header.actions, id: \.self) { action in
                            RoundActionButton(Self.title(of: action), systemImage: Self.symbol(of: action)) {
                                if action == .scan { scan() } else { header.perform(action) }
                            }
                            .disabled(header.disabled.contains(action))
                        }
                    }
                }
                if let notice = header.notice {
                    ErrorBanner(notice, style: .warning)
                        .brievieCard()
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    static func title(of action: PostHeader.Action) -> String {
        switch action {
        case .scan: DocumentStrings.actionScan
        case .search: DocumentStrings.actionSearch
        case .allRead: DocumentStrings.actionAllRead
        case .chooseName: DocumentStrings.actionChooseName
        }
    }

    static func symbol(of action: PostHeader.Action) -> String {
        switch action {
        case .scan: "doc.viewfinder"
        case .search: "magnifyingglass"
        case .allRead: "envelope.open"
        case .chooseName: "person.crop.circle.badge.questionmark"
        }
    }
}
#endif
