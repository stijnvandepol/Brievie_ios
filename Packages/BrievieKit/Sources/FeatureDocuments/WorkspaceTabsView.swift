#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// The models of one workspace's screens, made together by the app and dropped together on a workspace switch.
public struct WorkspaceScreens {
    public let tabs: WorkspaceTabsModel
    public let inbox: DocumentsModel
    public let myPost: DocumentsModel
    public let allPost: DocumentsModel
    public let tasks: MyTasksModel
    /// One scan flow per list: each pushes its preview on its own navigation stack.
    public let inboxScan: ScanFlowModel
    public let myPostScan: ScanFlowModel
    public let allPostScan: ScanFlowModel

    public init(
        tabs: WorkspaceTabsModel, inbox: DocumentsModel, myPost: DocumentsModel, allPost: DocumentsModel,
        tasks: MyTasksModel, inboxScan: ScanFlowModel, myPostScan: ScanFlowModel, allPostScan: ScanFlowModel
    ) {
        self.tabs = tabs
        self.inbox = inbox
        self.myPost = myPost
        self.allPost = allPost
        self.tasks = tasks
        self.inboxScan = inboxScan
        self.myPostScan = myPostScan
        self.allPostScan = allPostScan
    }
}

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
            NavigationStack { sidebarDetail }
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
        DocumentsView(
            model: screens.inbox, scanModel: screens.inboxScan, warning: warning,
            showMyTasks: { tabs.showTasks() }, showAllPost: { tabs.showAllPost() },
            destination: { id in destination(id, screens.inbox) },
            compare: { id in compare(id, screens.inbox) }
        )
        .toolbar { pillItem }
    }

    @ViewBuilder private var myPostRoot: some View {
        switch tabs.myPostSupport {
        case .supported:
            DocumentsView(model: screens.myPost, scanModel: screens.myPostScan, warning: warning) { id in
                destination(id, screens.myPost)
            } compare: { id in
                compare(id, screens.myPost)
            }
            .toolbar { pillItem }
        case .unknown, .notSupported:
            MyPostWaiting(failure: tabs.countFailure) { Task { await tabs.refreshCounts() } }
                .toolbar { pillItem }
        }
    }

    private var tasksRoot: some View {
        MyTasksView(model: screens.tasks) { id in destination(id, screens.inbox) }
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
        case .labels, .label:
            EmptyView()
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
