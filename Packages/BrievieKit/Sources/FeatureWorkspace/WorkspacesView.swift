#if os(iOS)
import BrievieUI
import SwiftUI

/// The paired user's workspaces, and the server they come from.
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
                    Section {
                        ErrorBanner(String(localized: "workspaces.noPasscode", bundle: .module), style: .warning)
                    }
                }
                Section {
                    content
                } header: {
                    Text("workspaces.section.workspaces", bundle: .module)
                }
                serverSection
            }
            .listStyle(.insetGrouped)
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
        }
    }

    private var serverSection: some View {
        Section {
            if let address = model.serverAddress {
                LabeledContent {
                    Text(address)
                } label: {
                    Text("workspaces.server.address", bundle: .module)
                }
            }
            LabeledContent {
                Label {
                    Text("workspaces.server.secure", bundle: .module)
                } icon: {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.green)
                }
            } label: {
                Text("workspaces.server.connection", bundle: .module)
            }
            LabeledContent {
                Text(model.userName)
            } label: {
                Text("workspaces.server.user", bundle: .module)
            }
        } header: {
            Text("workspaces.section.server", bundle: .module)
        } footer: {
            Text("workspaces.server.footer", bundle: .module)
        }
    }
}

private struct WorkspaceRowView: View {
    let row: WorkspacesModel.Row

    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.iconName)
                .font(.body.weight(.semibold))
                .foregroundStyle(BrievieColor.onBrand)
                .frame(width: tileSize, height: tileSize)
                .background(BrievieColor.brand, in: RoundedRectangle(cornerRadius: tileSize / 4, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.headline)
                Text(row.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
