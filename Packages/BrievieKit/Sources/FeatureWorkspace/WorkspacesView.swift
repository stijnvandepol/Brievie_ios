#if os(iOS)
import BrievieUI
import SwiftUI

/// The paired user's workspaces, and the server they come from.
public struct WorkspacesView<Destination: View>: View {
    private let model: WorkspacesModel
    /// The device has no passcode, so the app cannot lock itself.
    private let showsNoPasscodeWarning: Bool
    /// What a workspace opens: supplied by the app, so this target does not know the documents feature.
    private let destination: (WorkspacesModel.Row) -> Destination

    public init(
        model: WorkspacesModel,
        showsNoPasscodeWarning: Bool,
        @ViewBuilder destination: @escaping (WorkspacesModel.Row) -> Destination
    ) {
        self.model = model
        self.showsNoPasscodeWarning = showsNoPasscodeWarning
        self.destination = destination
    }

    public var body: some View {
        @Bindable var model = model
        NavigationStack {
            WorkspacesList(
                state: model.state,
                serverAddress: model.serverAddress,
                userName: model.userName,
                showsNoPasscodeWarning: showsNoPasscodeWarning,
                unpair: UnpairControl(
                    isUnpairing: model.isUnpairing,
                    isConfirming: $model.isConfirmingUnpair,
                    message: model.unpairMessage,
                    request: { model.requestUnpair() },
                    confirm: { model.confirmUnpair() }
                ),
                retry: { model.retry() },
                destination: destination
            )
            .refreshable { await model.load() }
            .task { await model.load() }
            .onDisappear { model.stop() }
        }
    }
}

/// What the "Ontkoppelen" section shows and does.
struct UnpairControl {
    let isUnpairing: Bool
    let isConfirming: Binding<Bool>
    let message: String
    let request: () -> Void
    let confirm: () -> Void
}

/// The rendering of `WorkspacesView`, free of the model so that previews can feed it plain values.
struct WorkspacesList<Destination: View>: View {
    let state: WorkspacesModel.State
    let serverAddress: String?
    let userName: String
    let showsNoPasscodeWarning: Bool
    let unpair: UnpairControl
    let retry: () -> Void
    let destination: (WorkspacesModel.Row) -> Destination

    var body: some View {
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
            // Its own section, last, away from everything else on the screen.
            unpairSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("workspaces.title", bundle: .module))
    }

    @ViewBuilder private var content: some View {
        switch state {
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
                NavigationLink {
                    destination(row)
                } label: {
                    WorkspaceRowView(row: row)
                }
            }
        case .failed(let message):
            ErrorBanner(message, actionTitle: String(localized: "workspaces.retry", bundle: .module), action: retry)
        }
    }

    private var serverSection: some View {
        Section {
            if let serverAddress {
                LabeledContent {
                    Text(serverAddress)
                } label: {
                    Text("workspaces.server.address", bundle: .module)
                }
            }
            LabeledContent {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .imageScale(.small)
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("workspaces.server.secure", bundle: .module)
                }
                .accessibilityElement(children: .combine)
            } label: {
                Text("workspaces.server.connection", bundle: .module)
            }
            LabeledContent {
                Text(userName)
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

extension WorkspacesList {
    private var unpairSection: some View {
        Section {
            Button(role: .destructive, action: unpair.request) {
                HStack {
                    Text("workspaces.unpair.button", bundle: .module)
                    if unpair.isUnpairing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(unpair.isUnpairing)
        }
        .confirmationDialog(
            Text("workspaces.unpair.title", bundle: .module),
            isPresented: unpair.isConfirming,
            titleVisibility: .visible
        ) {
            Button(role: .destructive, action: unpair.confirm) {
                Text("workspaces.unpair.confirm", bundle: .module)
            }
            Button(role: .cancel) {} label: {
                Text("workspaces.unpair.cancel", bundle: .module)
            }
        } message: {
            Text(unpair.message)
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

#if DEBUG
private var previewRows: [WorkspacesModel.Row] {
    [
        WorkspacesModel.Row(
            id: UUID(), name: "Thuis", kind: .home, kindLabel: WorkspaceStrings.kindHome,
            roleLabel: WorkspaceStrings.roleAdmin
        )
    ]
}

private var previewUnpair: UnpairControl {
    UnpairControl(
        isUnpairing: false, isConfirming: .constant(false), message: WorkspaceStrings.unpairMessage,
        request: {}, confirm: {}
    )
}

#Preview("Light") {
    NavigationStack {
        WorkspacesList(
            state: .loaded(previewRows), serverAddress: "brievie.local", userName: "Beheerder",
            showsNoPasscodeWarning: false, unpair: previewUnpair, retry: {}, destination: { _ in EmptyView() }
        )
    }
    .tint(BrievieColor.brand)
}

#Preview("Dark") {
    NavigationStack {
        WorkspacesList(
            state: .loaded(previewRows), serverAddress: "brievie.local", userName: "Beheerder",
            showsNoPasscodeWarning: false, unpair: previewUnpair, retry: {}, destination: { _ in EmptyView() }
        )
    }
    .tint(BrievieColor.brand)
    .preferredColorScheme(.dark)
}
#endif
#endif
