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
    @Environment(\.scenePhase) private var scenePhase

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
                    offersCalendarRemoval: model.offersCalendarRemoval,
                    request: { model.requestUnpair() },
                    confirm: { model.confirmUnpair() },
                    confirmRemovingCalendars: { model.confirmUnpair(removingCalendars: true) }
                ),
                retry: { model.retry() },
                calendarModel: { model.calendarModel(for: $0.id) },
                destination: destination
            )
            .refreshable { await model.load() }
            .task { await model.load() }
            .onDisappear { model.stop() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { model.sceneLeftForeground() }
            }
        }
    }
}

/// What the "Ontkoppelen" section shows and does.
struct UnpairControl {
    let isUnpairing: Bool
    let isConfirming: Binding<Bool>
    let message: String
    /// A calendar switch is on: a second choice also removes the calendars.
    let offersCalendarRemoval: Bool
    let request: () -> Void
    let confirm: () -> Void
    let confirmRemovingCalendars: () -> Void
}

/// The rendering of `WorkspacesView`, free of the model so that previews can feed it plain values.
struct WorkspacesList<Destination: View>: View {
    let state: WorkspacesModel.State
    let serverAddress: String?
    let userName: String
    let showsNoPasscodeWarning: Bool
    let unpair: UnpairControl
    let retry: () -> Void
    /// The calendar switch under a workspace; `nil` shows none.
    let calendarModel: (WorkspacesModel.Row) -> CalendarSettingModel?
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
                if let calendar = calendarModel(row) {
                    CalendarSwitchRow(model: calendar)
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
            if unpair.offersCalendarRemoval {
                Button(role: .destructive, action: unpair.confirmRemovingCalendars) {
                    Text("workspaces.unpair.confirmRemovingCalendars", bundle: .module)
                }
            }
            Button(role: .cancel) {} label: {
                Text("workspaces.unpair.cancel", bundle: .module)
            }
        } message: {
            Text(unpair.message)
        }
    }
}

/// "Zet deadlines in mijn agenda" under a workspace, with why it went back off and the "ook verwijderen?"
/// question when it is turned off.
private struct CalendarSwitchRow: View {
    @Bindable var model: CalendarSettingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The row sits under its workspace and the footer names the calendar: no subtitle with the name.
            Toggle(isOn: Binding(get: { model.isOn }, set: { model.toggle($0) })) {
                Text("workspaces.calendar.toggle", bundle: .module)
            }
            .accessibilityHint(model.switchHint)
            Text(model.footer)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let message = model.message {
                ErrorBanner(
                    message,
                    actionTitle: model.showsOpenSettings
                        ? String(localized: "workspaces.calendar.openSettings", bundle: .module) : nil,
                    action: { model.openSettings() }
                )
            }
        }
        .confirmationDialog(model.removeQuestion, isPresented: $model.isAskingToRemove, titleVisibility: .visible) {
            Button(role: .destructive) {
                model.switchOff(removeCalendar: true)
            } label: {
                Text("workspaces.calendar.remove", bundle: .module)
            }
            Button {
                model.switchOff(removeCalendar: false)
            } label: {
                Text("workspaces.calendar.keep", bundle: .module)
            }
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
        offersCalendarRemoval: true, request: {}, confirm: {}, confirmRemovingCalendars: {}
    )
}

#Preview("Light") {
    NavigationStack {
        WorkspacesList(
            state: .loaded(previewRows), serverAddress: "brievie.local", userName: "Beheerder",
            showsNoPasscodeWarning: false, unpair: previewUnpair, retry: {}, calendarModel: { _ in nil },
            destination: { _ in EmptyView() }
        )
    }
    .tint(BrievieColor.brand)
}

#Preview("Dark") {
    NavigationStack {
        WorkspacesList(
            state: .loaded(previewRows), serverAddress: "brievie.local", userName: "Beheerder",
            showsNoPasscodeWarning: false, unpair: previewUnpair, retry: {}, calendarModel: { _ in nil },
            destination: { _ in EmptyView() }
        )
    }
    .tint(BrievieColor.brand)
    .preferredColorScheme(.dark)
}
#endif
#endif
