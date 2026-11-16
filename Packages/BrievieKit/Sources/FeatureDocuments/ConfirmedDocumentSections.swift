#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// A confirmed letter: what it is, its summary, and on a 1c server `ConfirmedDocumentSections`; on a 1b server
/// the tasks as they are.
struct DoneSections: View {
    let detail: DocumentDetail
    let confirmed: ConfirmedDocumentModel?
    let onPick: (OrganisePicker) -> Void
    let onShowQuote: (String) -> Void

    var body: some View {
        Section {
            LabeledContent(DocumentStrings.sender, value: detail.summary.sender)
            LabeledContent(
                DocumentStrings.documentType, value: DocumentTypes.documentTypeLabel(detail.summary.documentType)
            )
            if let date = detail.summary.letterDate {
                LabeledContent(DocumentStrings.letterDate, value: date.display)
            }
        }
        if !detail.summaryText.isEmpty {
            Section {
                Text(detail.summaryText)
            } header: {
                Text(DocumentStrings.summary)
            } footer: {
                if detail.summaryByAI {
                    Label(DocumentStrings.summaryByAI, systemImage: "sparkles")
                }
            }
        }
        if let confirmed {
            ConfirmedDocumentSections(model: confirmed, onPick: onPick, onShowQuote: onShowQuote)
        } else {
            Section {
                if detail.tasks.isEmpty {
                    Text(DocumentStrings.noTasks)
                        .foregroundStyle(.secondary)
                }
                ForEach(detail.tasks) { task in
                    ConfirmedTaskRow(task: task) { onShowQuote(task.deadlineQuote) }
                }
            } header: {
                Text(DocumentStrings.tasks)
            }
        }
    }
}

/// A confirmed letter on a 1c server: "Op naam van" and "Labels" (editable for a member, plain for a viewer)
/// and the tasks with a tick box. Every change is sent at once; there is no save button.
struct ConfirmedDocumentSections: View {
    let model: ConfirmedDocumentModel
    let onPick: (OrganisePicker) -> Void
    let onShowQuote: (String) -> Void

    var body: some View {
        if let error = model.changeError {
            Section { ErrorBanner(error) }
        }
        OrganiseSection(
            draft: model.organise, persons: model.persons, labels: model.labels,
            actions: model.canEdit ? actions : nil, onShowQuote: onShowQuote
        )
        Section {
            if model.tasks.isEmpty {
                Text(DocumentStrings.noTasks)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.tasks) { task in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    TaskTickBox(task: task, isEditable: model.canEdit) {
                        Task { await model.setTask(task.id, done: !task.isDone) }
                    }
                    ConfirmedTaskRow(task: task) { onShowQuote(task.deadlineQuote) }
                }
            }
        } header: {
            Text(DocumentStrings.confirmedTasks)
        }
    }

    private var actions: OrganiseActions {
        OrganiseActions(
            setAddressees: { ids in Task { await model.setAddressees(ids) } },
            setLabels: { ids in Task { await model.setLabels(ids) } },
            proposals: .acceptOrDismiss(
                accept: { suggestion in Task { await model.accept(suggestion) } },
                dismiss: { suggestion in Task { await model.dismiss(suggestion) } }
            ),
            pickPersons: { onPick(.persons) },
            pickLabels: { onPick(.labels) }
        )
    }
}

/// The person or label list for a confirmed letter: every tick is sent at once.
struct ConfirmedPicker: View {
    let model: ConfirmedDocumentModel
    let picker: OrganisePicker
    let close: () -> Void

    var body: some View {
        switch picker {
        case .persons:
            PersonPickerView(
                persons: model.persons,
                selection: Binding(
                    get: { model.organise.addresseeIDs },
                    set: { ids in Task { await model.setAddressees(ids) } }
                ),
                error: model.personError, onCreate: { await model.createPerson(named: $0) }, close: close
            )
        case .labels:
            LabelPickerView(
                labels: model.labels,
                selection: Binding(
                    get: { model.organise.labelIDs },
                    set: { ids in Task { await model.setLabels(ids) } }
                ),
                close: close
            )
        }
    }
}

/// Whether a task is done: a box to tick for a member, the same mark without a button for a viewer.
/// VoiceOver reads the task's text with "afgerond" or "open".
private struct TaskTickBox: View {
    let task: ConfirmedTask
    let isEditable: Bool
    let toggle: () -> Void

    var body: some View {
        if isEditable {
            Button(action: toggle) { mark }
                .buttonStyle(.borderless)
                .accessibilityLabel(task.description)
                .accessibilityValue(value)
        } else {
            mark
                .accessibilityElement()
                .accessibilityLabel(task.description)
                .accessibilityValue(value)
        }
    }

    private var mark: some View {
        Image(systemName: symbol)
            .font(.title2)
            .foregroundStyle(task.isDone ? Color.accentColor : Color.secondary)
    }

    private var symbol: String {
        if task.isDone { return "checkmark.circle.fill" }
        return "circle"
    }

    private var value: String { task.isDone ? DocumentStrings.taskDone : DocumentStrings.taskOpen }
}

/// A confirmed task: what to do, by when, and where the deadline stands in the letter.
struct ConfirmedTaskRow: View {
    let task: ConfirmedTask
    let showSource: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.description)
                .font(.headline)
            Text(String(
                format: DocumentStrings.taskLineFormat,
                DocumentTypes.taskTypeLabel(task.type), task.deadline?.display ?? DocumentStrings.noDeadline
            ))
            .font(.subheadline)
            if task.deadlineQuote.isEmpty {
                if task.deadline != nil {
                    Text(DocumentStrings.manualSource)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(String(format: DocumentStrings.sourceFormat, task.deadlineQuote))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(DocumentStrings.whereIsThis, action: showSource)
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
