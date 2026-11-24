#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// The settings: the deadline reminders, the calendar switch of each workspace, the server and "Ontkoppelen". The
/// workspace is chosen with the pill at the top of the post (`WorkspacePickerSheet`), not here.
public struct SettingsView: View {
    let model: WorkspacesModel

    public init(model: WorkspacesModel) {
        self.model = model
    }

    public var body: some View {
        @Bindable var model = model
        SettingsList(
            state: model.state,
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
            reminders: model.reminderModel
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
    let serverAddress: String?
    let userName: String
    let unpair: UnpairControl
    let retry: () -> Void
    /// The calendar switch under a workspace; `nil` shows none.
    let calendarModel: (WorkspacesModel.Row) -> CalendarSettingModel?
    /// "Meldingen voor termijnen"; `nil` shows no section.
    var reminders: ReminderSettingModel?

    var body: some View {
        List {
            if let reminders {
                ReminderSettingsSection(model: reminders)
            }
            calendarSections
            serverSection
            // Its own section, last, away from everything else on the screen.
            unpairSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("settings.title", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "Agenda": the calendar switch of each workspace, under the workspace's name when there is more than one.
    /// While the workspaces load or failed to load, the state stands here.
    @ViewBuilder private var calendarSections: some View {
        switch state {
        case .loading:
            Section { WorkspacesLoadingRow() } header: { Text("settings.section.calendar", bundle: .module) }
        case .failed(let message):
            Section {
                WorkspacesErrorRow(message: message, retry: retry)
            } header: {
                Text("settings.section.calendar", bundle: .module)
            }
        case .loaded(let rows):
            let calendars = rows.compactMap { row in calendarModel(row).map { (row, $0) } }
            ForEach(calendars, id: \.0.id) { row, calendar in
                Section {
                    CalendarSwitchRows(model: calendar)
                } header: {
                    if rows.count > 1 {
                        Text(String(format: WorkspaceStrings.calendarSectionFormat, row.name))
                    } else {
                        Text("settings.section.calendar", bundle: .module)
                    }
                }
            }
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

/// "Zet termijnen in mijn agenda" of one workspace, with why it went back off and the "ook verwijderen?" question
/// when it is turned off. Each control is a row of its own: in one shared row a tap had to be held before the
/// switch reacted (seen in the simulator, 21-11-2026).
private struct CalendarSwitchRows: View {
    @Bindable var model: CalendarSettingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { model.isOn }, set: { model.toggle($0) })) {
                Text("workspaces.calendar.toggle", bundle: .module)
            }
            .accessibilityHint(model.switchHint)
            Text(model.footer)
                .font(.footnote)
                .foregroundStyle(.secondary)
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
        if model.isOn {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(get: { model.showsDetails }, set: { model.setShowsDetails($0) })) {
                    Text("workspaces.calendar.details.toggle", bundle: .module)
                }
                .accessibilityHint(model.detailsFooter)
                Text(model.detailsFooter)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Picker(
                    WorkspaceStrings.calendarTasksLabel,
                    selection: Binding(get: { model.taskPart }, set: { model.setTaskPart($0) })
                ) {
                    Text(WorkspaceStrings.calendarTasksMine).tag(MyTasksPart.mine)
                    Text(WorkspaceStrings.calendarTasksAll).tag(MyTasksPart.all)
                }
                .accessibilityHint(WorkspaceStrings.calendarTasksFooter)
                Text(WorkspaceStrings.calendarTasksFooter)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
            state: state, serverAddress: "brievie.local", userName: "Beheerder",
            unpair: previewUnpair, retry: {}, calendarModel: { _ in nil }
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
