#if os(iOS)
import BrievieUI
import SwiftUI

/// The settings: the workspaces (which one the inbox shows, and the calendar switch of each), the reminders, the
/// server and "Ontkoppelen". Pushed from the root screen by `WorkspaceRootView`.
struct SettingsView: View {
    let model: WorkspacesModel
    /// The user chose a workspace: back to the inbox, which now shows it.
    let didChoose: () -> Void

    var body: some View {
        @Bindable var model = model
        SettingsList(
            state: model.state,
            currentWorkspaceID: model.currentWorkspaceID,
            serverAddress: model.serverAddress,
            userName: model.userName,
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
            reminders: model.reminderModel,
            choose: { workspace in
                model.select(workspace)
                didChoose()
            }
        )
        .refreshable { await model.load() }
        // Each visit loads the list again, and with it syncs the calendars and checks calendar access.
        .task { await model.load() }
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

/// The rendering of `SettingsView`, free of the model so that previews can feed it plain values.
struct SettingsList: View {
    let state: WorkspacesModel.State
    /// The workspace the inbox shows: it carries the checkmark.
    let currentWorkspaceID: UUID?
    let serverAddress: String?
    let userName: String
    let unpair: UnpairControl
    let retry: () -> Void
    /// The calendar switch under a workspace; `nil` shows none.
    let calendarModel: (WorkspacesModel.Row) -> CalendarSettingModel?
    /// "Meldingen voor termijnen"; `nil` shows no section.
    var reminders: ReminderSettingModel?
    /// The user tapped a workspace.
    let choose: (UUID) -> Void

    var body: some View {
        List {
            Section {
                content
            } header: {
                Text("workspaces.section.workspaces", bundle: .module)
            }
            if let reminders {
                ReminderSettingsSection(model: reminders)
            }
            serverSection
            // Its own section, last, away from everything else on the screen.
            unpairSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("settings.title", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            WorkspacesLoadingRow()
        case .loaded(let rows):
            if rows.isEmpty {
                WorkspacesEmptyRow()
            }
            ForEach(rows) { row in
                workspaceButton(row)
                if let calendar = calendarModel(row) {
                    CalendarSwitchRow(model: calendar)
                }
            }
        case .failed(let message):
            WorkspacesErrorRow(message: message, retry: retry)
        }
    }

    private func workspaceButton(_ row: WorkspacesModel.Row) -> some View {
        let isCurrent = row.id == currentWorkspaceID
        return Button {
            choose(row.id)
        } label: {
            HStack(spacing: 12) {
                WorkspaceRowView(row: row)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(.primary)
        }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityHint(isCurrent ? Text(verbatim: "") : Text("settings.workspace.hint", bundle: .module))
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

extension SettingsList {
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

/// "Zet termijnen in mijn agenda" under a workspace, with why it went back off and the "ook verwijderen?"
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
            if model.isOn {
                Toggle(isOn: Binding(get: { model.showsDetails }, set: { model.setShowsDetails($0) })) {
                    Text("workspaces.calendar.details.toggle", bundle: .module)
                }
                .accessibilityHint(model.detailsFooter)
                Text(model.detailsFooter)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
        // Only another account is left: the user decides, by that account's name.
        .alert(model.consentQuestion, isPresented: $model.isAskingConsent) {
            Button {
                model.answerConsent(true)
            } label: {
                Text("workspaces.calendar.consent.yes", bundle: .module)
            }
            Button(role: .cancel) {
                model.answerConsent(false)
            } label: {
                Text("workspaces.calendar.consent.no", bundle: .module)
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
            id: previewCurrent, name: "Thuis", kind: .home, kindLabel: WorkspaceStrings.kindHome,
            roleLabel: WorkspaceStrings.roleAdmin
        ),
        WorkspacesModel.Row(
            id: UUID(), name: "Bakkerij", kind: .business, kindLabel: WorkspaceStrings.kindBusiness,
            roleLabel: WorkspaceStrings.roleMember
        )
    ]
}

private let previewCurrent = UUID()

private var previewUnpair: UnpairControl {
    UnpairControl(
        isUnpairing: false, isConfirming: .constant(false), message: WorkspaceStrings.unpairMessage,
        offersCalendarRemoval: true, request: {}, confirm: {}, confirmRemovingCalendars: {}
    )
}

@MainActor
private func previewSettings(_ state: WorkspacesModel.State) -> some View {
    NavigationStack {
        SettingsList(
            state: state, currentWorkspaceID: previewCurrent, serverAddress: "brievie.local", userName: "Beheerder",
            unpair: previewUnpair, retry: {}, calendarModel: { _ in nil }, choose: { _ in }
        )
    }
    .tint(BrievieColor.brand)
}

#Preview("Light") {
    previewSettings(.loaded(previewRows))
}

#Preview("Dark") {
    previewSettings(.loaded(previewRows))
        .preferredColorScheme(.dark)
}

#Preview("Failed") {
    previewSettings(.failed(message: WorkspaceStrings.unreachable))
}
#endif
#endif
