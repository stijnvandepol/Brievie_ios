#if os(iOS)
import BrievieUI
import SwiftUI

/// "Meldingen voor termijnen" in the settings: the switch, what a reminder shows and when, and while it is on
/// the lead time and "Toon de afzender in meldingen".
struct ReminderSettingsSection: View {
    @Bindable var model: ReminderSettingModel

    var body: some View {
        Section {
            Toggle(WorkspaceStrings.remindersToggle, isOn: Binding(get: { model.isOn }, set: { model.toggle($0) }))
                .accessibilityHint(model.footer)
            if let message = model.message {
                ErrorBanner(
                    message,
                    actionTitle: model.showsOpenSettings ? WorkspaceStrings.remindersOpenSettings : nil,
                    action: { model.openSettings() }
                )
            }
            if model.isOn {
                StackedPicker(
                    WorkspaceStrings.remindersLead,
                    selection: Binding(get: { model.leadDays }, set: { model.setLeadDays($0) })
                ) {
                    ForEach(model.leadOptions, id: \.days) { option in
                        Text(option.title).tag(option.days)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(
                        WorkspaceStrings.remindersSenderToggle,
                        isOn: Binding(get: { model.showsSender }, set: { model.setShowsSender($0) })
                    )
                    .accessibilityHint(WorkspaceStrings.remindersSenderFooter)
                    Text(WorkspaceStrings.remindersSenderFooter)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(WorkspaceStrings.remindersHeader)
        } footer: {
            Text(model.footer)
        }
    }
}
#endif
