#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// A workspace on the iPhone: a tab bar with Inbox, Mijn post, Taken and Meer (in the web's order), opening on
/// "Mijn post". On an iPad (regular width) a sidebar in the web's order, "Instellingen" at the bottom; in compact
/// width it falls back to the tabs. Every root carries the workspace pill at the top left.
public struct WorkspaceTabsView<Destination: View, Compare: View, Pill: View, Settings: View>: View {
    private let screens: WorkspaceScreens
    private let warning: String?
    /// The letter screen; the model is the list that opened it (it offers the undo after "Verwijderen").
    private let destination: (UUID, DocumentsModel) -> Destination
    private let compare: (UUID, DocumentsModel) -> Compare
    private let pill: () -> Pill
    private let settings: () -> Settings
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(
        screens: WorkspaceScreens, warning: String?,
        @ViewBuilder destination: @escaping (UUID, DocumentsModel) -> Destination,
        @ViewBuilder compare: @escaping (UUID, DocumentsModel) -> Compare,
        @ViewBuilder pill: @escaping () -> Pill,
        @ViewBuilder settings: @escaping () -> Settings
    ) {
        self.screens = screens
        self.warning = warning
        self.destination = destination
        self.compare = compare
        self.pill = pill
        self.settings = settings
    }

    private var tabs: WorkspaceTabsModel { screens.tabs }

    public var body: some View {
        Group {
            if sizeClass == .regular {
                sidebarLayout
            } else {
                tabLayout
            }
        }
        .task { await tabs.refreshCounts() }
    }

    // MARK: - iPhone

    private var tabLayout: some View {
        @Bindable var tabs = tabs
        return TabView(selection: $tabs.selection) {
            ForEach(tabs.tabs, id: \.self) { tab in
                tabRoot(tab)
                    .tabItem { Label(Self.title(of: tab), systemImage: Self.symbol(of: tab)) }
                    .badge(tabs.badge(for: tab) ?? 0)
                    .tag(tab)
            }
        }
    }

    @ViewBuilder private func tabRoot(_ tab: WorkspaceTabsModel.Tab) -> some View {
        @Bindable var tabs = tabs
        switch tab {
        case .inbox:
            NavigationStack { inboxRoot }
        case .myPost:
            NavigationStack { myPostRoot }
        case .tasks:
            NavigationStack { tasksRoot }
        case .more:
            NavigationStack(path: $tabs.morePath) {
                MoreList(hasTrash: tabs.hasTrash, open: { tabs.morePath.append($0) })
                    .toolbar { pillItem }
                    .navigationDestination(for: WorkspaceTabsModel.Place.self) { place(_: $0) }
            }
        }
    }

    // MARK: - iPad

    private var sidebarLayout: some View {
        @Bindable var tabs = tabs
        return NavigationSplitView {
            List(selection: $tabs.sidebarSelection) {
                Section {
                    ForEach(tabs.sidebarItems, id: \.self) { item in
                        sidebarRow(item)
                    }
                }
                Section {
                    sidebarRow(.settings)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { pill() } }
        } detail: {
            NavigationStack(path: $tabs.detailPath) {
                sidebarDetail
                    .navigationDestination(for: WorkspaceTabsModel.Place.self) { place(_: $0) }
            }
            // Another place is another stack: nothing pushed in one shows in the next.
            .id(tabs.sidebarSelection)
        }
    }

    private func sidebarRow(_ item: WorkspaceTabsModel.SidebarItem) -> some View {
        Label(Self.title(of: item), systemImage: Self.symbol(of: item))
            .badge(sidebarBadge(item) ?? 0)
            .tag(item)
    }

    @ViewBuilder private var sidebarDetail: some View {
        switch tabs.sidebarSelection ?? .myPost {
        case .inbox: inboxRoot
        case .myPost: myPostRoot
        case .tasks: tasksRoot
        case .allPost: place(.allPost)
        case .labels: place(.labels)
        case .trash: place(.trash)
        case .settings: place(.settings)
        }
    }

    // MARK: - Roots

    /// The pill on every root; on an iPad it stands once, above the sidebar.
    @ToolbarContentBuilder private var pillItem: some ToolbarContent {
        if sizeClass != .regular {
            ToolbarItem(placement: .topBarLeading) { pill() }
        }
    }

    private var inboxRoot: some View {
        @Bindable var tabs = tabs
        return DocumentsView(
            model: screens.inbox, scanModel: screens.inboxScan, warning: warning,
            showMyTasks: { tabs.showTasks() }, showAllPost: { tabs.showAllPost() }, header: inboxHeader,
            destination: { id in destination(id, screens.inbox) },
            compare: { id in compare(id, screens.inbox) }
        )
        .toolbar { pillItem }
        .navigationDestination(isPresented: $tabs.isShowingLingering) {
            LingeringView(model: screens.lingering) { id in destination(id, screens.inbox) }
        }
    }

    /// The Inbox: for sorters in an organisation the "Blijft liggen" card; Scannen and Naam kiezen.
    private var inboxHeader: PostHeader {
        let list = screens.inbox
        var actions: [PostHeader.Action] = []
        if list.canScan { actions += [.scan, .chooseName] }
        return PostHeader(
            cards: tabs.cards.filter { $0.kind == .lingering }, actions: actions,
            disabled: list.firstLetterNeedingName == nil ? [.chooseName] : [],
            openCard: { _ in tabs.isShowingLingering = true },
            perform: { action in
                if action == .chooseName, let id = list.firstLetterNeedingName { list.openedDocument = id }
            }
        )
    }

    @ViewBuilder private var myPostRoot: some View {
        switch tabs.myPostSupport {
        case .supported:
            DocumentsView(
                model: screens.myPost, scanModel: screens.myPostScan, warning: warning, header: myPostHeader,
                destination: { id in destination(id, screens.myPost) },
                compare: { id in compare(id, screens.myPost) }
            )
            .toolbar { pillItem }
        case .unknown, .notSupported:
            MyPostWaiting(failure: tabs.countFailure) { Task { await tabs.refreshCounts() } }
                .toolbar { pillItem }
        }
    }

    /// Mijn post: unread, tasks and (for sorters) what lies too long; Scannen, Zoeken, Alles gelezen.
    private var myPostHeader: PostHeader {
        let list = screens.myPost
        var actions: [PostHeader.Action] = []
        if list.canScan { actions.append(.scan) }
        actions.append(.search)
        if list.offersReading { actions.append(.allRead) }
        return PostHeader(
            cards: tabs.cards, actions: actions, disabled: list.hasUnreadRows ? [] : [.allRead],
            notice: tabs.lacksPerson ? DocumentStrings.myPostNoPerson : nil,
            openCard: { kind in
                switch kind {
                case .unread: Task { await list.select(.myPostUnread) }
                case .tasks: tabs.showTasks()
                case .lingering: tabs.showLingering()
                }
            },
            perform: { action in
                switch action {
                case .search: tabs.showSearch()
                case .allRead: Task { await list.markAllRead() }
                case .scan, .chooseName: break
                }
            }
        )
    }

    private var tasksRoot: some View {
        MyTasksView(model: screens.tasks, trashList: screens.inbox) { id in destination(id, screens.inbox) }
            .toolbar { pillItem }
    }

    @ViewBuilder private func place(_ place: WorkspaceTabsModel.Place) -> some View {
        switch place {
        case .allPost:
            DocumentsView(model: screens.allPost, scanModel: screens.allPostScan, warning: nil) { id in
                destination(id, screens.allPost)
            } compare: { id in
                compare(id, screens.allPost)
            }
        case .labels:
            LabelsView(model: screens.labels) { id in
                if sizeClass == .regular {
                    tabs.detailPath.append(WorkspaceTabsModel.Place.label(id))
                } else {
                    tabs.morePath.append(WorkspaceTabsModel.Place.label(id))
                }
            }
        case let .label(id):
            LabelPostScreen(label: id, from: screens.allPost, destination: destination, compare: compare)
        case .trash:
            TrashScreen(model: screens.allPost)
        case .settings:
            settings()
        }
    }

    // MARK: - Words

    private func sidebarBadge(_ item: WorkspaceTabsModel.SidebarItem) -> Int? {
        switch item {
        case .inbox: tabs.badge(for: .inbox)
        case .myPost: tabs.badge(for: .myPost)
        case .tasks: tabs.badge(for: .tasks)
        case .allPost, .labels, .trash, .settings: nil
        }
    }

    static func title(of tab: WorkspaceTabsModel.Tab) -> String {
        switch tab {
        case .inbox: DocumentStrings.scopeInbox
        case .myPost: DocumentStrings.scopeMyPost
        case .tasks: DocumentStrings.tabTasks
        case .more: DocumentStrings.tabMore
        }
    }

    static func symbol(of tab: WorkspaceTabsModel.Tab) -> String {
        switch tab {
        case .inbox: "tray"
        case .myPost: "envelope"
        case .tasks: "checklist"
        case .more: "ellipsis.circle"
        }
    }

    static func title(of item: WorkspaceTabsModel.SidebarItem) -> String {
        switch item {
        case .inbox: DocumentStrings.scopeInbox
        case .myPost: DocumentStrings.scopeMyPost
        case .tasks: DocumentStrings.myTasksTitle
        case .allPost: DocumentStrings.scopeAll
        case .labels: DocumentStrings.labelsTitle
        case .trash: DocumentStrings.trashTitle
        case .settings: DocumentStrings.settingsTitle
        }
    }

    static func symbol(of item: WorkspaceTabsModel.SidebarItem) -> String {
        switch item {
        case .inbox: "tray"
        case .myPost: "envelope"
        case .tasks: "checklist"
        case .allPost: "tray.full"
        case .labels: "tag"
        case .trash: "trash"
        case .settings: "gearshape"
        }
    }
}

/// "Meer": the rest of the web's menu, in its order.
struct MoreList: View {
    let hasTrash: Bool
    let open: (WorkspaceTabsModel.Place) -> Void

    var body: some View {
        List {
            Section {
                row(DocumentStrings.scopeAll, symbol: "tray.full", place: .allPost)
                row(DocumentStrings.labelsTitle, symbol: "tag", place: .labels)
                if hasTrash {
                    row(DocumentStrings.trashTitle, symbol: "trash", place: .trash)
                }
            }
            Section {
                row(DocumentStrings.settingsTitle, symbol: "gearshape", place: .settings)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(DocumentStrings.tabMore)
        .navigationBarTitleDisplayMode(.large)
    }

    private func row(_ title: String, symbol: String, place: WorkspaceTabsModel.Place) -> some View {
        Button {
            open(place)
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// "Mijn post" while the server has not said yet whether it knows it.
private struct MyPostWaiting: View {
    let failure: String?
    let retry: () -> Void

    var body: some View {
        List {
            Section {
                if let failure {
                    ErrorBanner(failure, actionTitle: DocumentStrings.retry, action: retry)
                } else {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(DocumentStrings.loading)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(DocumentStrings.scopeMyPost)
        .navigationBarTitleDisplayMode(.large)
    }
}

/// The Prullenbak, with its model made once per visit.
private struct TrashScreen: View {
    @State private var model: TrashModel

    init(model: DocumentsModel) {
        _model = State(initialValue: model.makeTrashModel())
    }

    var body: some View {
        TrashView(model: model)
    }
}
#endif
