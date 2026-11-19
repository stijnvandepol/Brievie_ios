#if os(iOS)
import BrievieUI
import SwiftUI

/// The paired app's root: the inbox of the current workspace, with the settings behind a gear in its navigation
/// bar. While the workspaces load, when they cannot be loaded or when there are none, the root says so, and the
/// gear stays there, so "Ontkoppelen" can always be reached.
public struct WorkspaceRootView<Inbox: View>: View {
    private let model: WorkspacesModel
    /// A warning above everything on the root screen (the device has no passcode); `nil` for none. The inbox
    /// shows it itself: the app passes it to both.
    private let warning: String?
    /// The post of a workspace: supplied by the app, so this target does not know the documents feature.
    private let inbox: (WorkspacesModel.Row) -> Inbox
    @Environment(\.scenePhase) private var scenePhase

    public init(
        model: WorkspacesModel,
        warning: String?,
        @ViewBuilder inbox: @escaping (WorkspacesModel.Row) -> Inbox
    ) {
        self.model = model
        self.warning = warning
        self.inbox = inbox
    }

    public var body: some View {
        @Bindable var model = model
        NavigationStack {
            root
                // Outside the root's states: whatever the root shows, the gear is there.
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
                // In the model: a tapped reminder closes the settings to show its letter.
                .navigationDestination(isPresented: $model.isShowingSettings) {
                    SettingsView(model: model) { model.isShowingSettings = false }
                }
        }
        .task { await model.load() }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.sceneLeftForeground() }
        }
    }

    @ViewBuilder private var root: some View {
        if case .inbox(let row) = model.root {
            inbox(row)
        } else {
            RootStatusList(root: model.root, warning: warning, retry: { model.retry() })
                .refreshable { await model.load() }
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
