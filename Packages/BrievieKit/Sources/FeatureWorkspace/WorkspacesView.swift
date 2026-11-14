#if os(iOS)
import BrievieUI
import SwiftUI

/// The paired user's workspaces.
public struct WorkspacesView: View {
    private let model: WorkspacesModel
    /// The device has no passcode, so the app cannot lock itself.
    private let showsNoPasscodeWarning: Bool

    public init(model: WorkspacesModel, showsNoPasscodeWarning: Bool) {
        self.model = model
        self.showsNoPasscodeWarning = showsNoPasscodeWarning
    }

    public var body: some View {
        NavigationStack {
            List {
                if showsNoPasscodeWarning {
                    ErrorBanner(String(localized: "workspaces.noPasscode", bundle: .module), style: .warning)
                        .listRowSeparator(.hidden)
                }
                content
            }
            .listStyle(.plain)
            .navigationTitle(Text("workspaces.title", bundle: .module))
            .refreshable { await model.load() }
            .task { await model.load() }
            .onDisappear { model.stop() }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text("workspaces.loading", bundle: .module)
            }
            .accessibilityElement(children: .combine)
        case .loaded(let rows):
            if rows.isEmpty {
                Text("workspaces.empty", bundle: .module)
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                WorkspaceRowView(row: row)
            }
        case .failed(let message):
            ErrorBanner(message, actionTitle: String(localized: "workspaces.retry", bundle: .module)) {
                model.retry()
            }
            .listRowSeparator(.hidden)
        }
    }
}

private struct WorkspaceRowView: View {
    let row: WorkspacesModel.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.name)
                .font(.headline)
            Text(row.kindLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let roleLabel = row.roleLabel {
                Text(roleLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
#endif
