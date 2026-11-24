#if os(iOS)
import BrievieUI
import SwiftUI

/// The paired app's root: the screens of the current workspace (tabs, with "Instellingen" under "Meer"). While the
/// workspaces load, when they cannot be loaded or when there are none, the root says so, with a gear to the settings,
/// so "Ontkoppelen" can always be reached.
public struct WorkspaceRootView<Content: View>: View {
    private let model: WorkspacesModel
    /// A warning above everything on the root screen (the device has no passcode); `nil` for none. The post
    /// shows it itself: the app passes it to both.
    private let warning: String?
    /// The screens of a workspace: supplied by the app, so this target does not know the documents feature.
    private let content: (WorkspacesModel.Row) -> Content
    @Environment(\.scenePhase) private var scenePhase

    public init(
        model: WorkspacesModel,
        warning: String?,
        @ViewBuilder content: @escaping (WorkspacesModel.Row) -> Content
    ) {
        self.model = model
        self.warning = warning
        self.content = content
    }

    public var body: some View {
        @Bindable var model = model
        root
            .sheet(isPresented: $model.isShowingPicker) {
                WorkspacePickerSheet(model: model)
            }
            .task { await model.load() }
            .onDisappear { model.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { model.sceneLeftForeground() }
            }
    }

    @ViewBuilder private var root: some View {
        @Bindable var model = model
        if case .inbox(let row) = model.root {
            content(row)
        } else {
            NavigationStack {
                RootStatusList(root: model.root, warning: warning, retry: { model.retry() })
                    .refreshable { await model.load() }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                model.isShowingSettings = true
                            } label: {
                                Label {
                                    Text("settings.title", bundle: .module)
                                } icon: {
                                    Image(systemName: "gearshape")
                                }
                            }
                        }
                    }
                    .navigationDestination(isPresented: $model.isShowingSettings) {
                        SettingsView(model: model)
                    }
            }
        }
    }
}

/// The root while there is no inbox to show: loading, the error with "Opnieuw proberen", or no workspaces.
struct RootStatusList: View {
    let root: WorkspacesModel.Root
    let warning: String?
    let retry: () -> Void

    var body: some View {
        List {
            if let warning {
                Section {
                    ErrorBanner(warning, style: .warning)
                }
            }
            Section {
                switch root {
                case .loading:
                    WorkspacesLoadingRow()
                case .failed(let message):
                    WorkspacesErrorRow(message: message, retry: retry)
                case .empty:
                    WorkspacesEmptyRow()
                case .inbox:
                    EmptyView()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("home.title", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "Werkruimtes laden...", on the root and in the settings.
struct WorkspacesLoadingRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("workspaces.loading", bundle: .module)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A first load that failed, with "Opnieuw proberen".
struct WorkspacesErrorRow: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ErrorBanner(message, actionTitle: String(localized: "workspaces.retry", bundle: .module), action: retry)
    }
}

/// "Je hebt nog geen werkruimtes."
struct WorkspacesEmptyRow: View {
    var body: some View {
        Text("workspaces.empty", bundle: .module)
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
private let previewWarning = "Dit apparaat heeft geen toegangscode. Stel een toegangscode in om je post te beschermen."

#Preview("Loading, no passcode") {
    NavigationStack {
        RootStatusList(root: .loading, warning: previewWarning, retry: {})
    }
    .tint(BrievieColor.brand)
}

#Preview("Failed") {
    NavigationStack {
        RootStatusList(root: .failed(message: WorkspaceStrings.unreachable), warning: nil, retry: {})
    }
    .tint(BrievieColor.brand)
}

#Preview("Empty, dark") {
    NavigationStack {
        RootStatusList(root: .empty, warning: nil, retry: {})
    }
    .tint(BrievieColor.brand)
    .preferredColorScheme(.dark)
}
#endif
#endif
