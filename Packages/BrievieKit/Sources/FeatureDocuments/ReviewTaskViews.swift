#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// A task's termijn. "Datum toevoegen" opens a calendar on today, but the termijn stays empty until the user taps
/// a day or "Vandaag": a tap that only looks never sets one (seen in the simulator, 20-11-2026).
/// A task's termijn and, on a payment, its amount, each with where it was read.
struct DeadlineAndAmountRows: View {
    let model: ReviewModel
    @Binding var task: TaskDraft

    var body: some View {
        DeadlineRow(model: model, taskID: task.id, deadline: task.deadline)
        FieldNotes(draft: model.draft, field: .taskDeadline(task.id), title: DocumentStrings.deadline) {
            model.showQuote($0)
        }
        if task.type == "pay" {
            AmountRow(amount: $task.amount, isValid: model.amountIsValid(for: task.id))
            FieldNotes(draft: model.draft, field: .taskAmount(task.id), title: DocumentStrings.amount) {
                model.showQuote($0)
            }
        }
    }
}

/// The amount of a payment task, in the user's own notation; an unreadable one says so (and blocks confirming).
struct AmountRow: View {
    @Binding var amount: String
    let isValid: Bool

    var body: some View {
        LabeledContent(DocumentStrings.amount) {
            TextField(DocumentStrings.amountPlaceholder, text: $amount)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
        if !isValid {
            ErrorBanner(DocumentStrings.amountUnreadable, style: .warning)
        }
    }
}

struct DeadlineRow: View {
    let model: ReviewModel
    let taskID: UUID
    let deadline: CalendarDate?

    var body: some View {
        if let deadline {
            DatePicker(
                DocumentStrings.deadline,
                selection: Binding(
                    get: { deadline.date(in: .current) },
                    set: { model.setDeadline(CalendarDate($0, in: .current), for: taskID) }
                ),
                displayedComponents: .date
            )
            .accessibilityHint(DocumentStrings.deadlineHint)
            Button(DocumentStrings.removeDate, role: .destructive) { model.setDeadline(nil, for: taskID) }
                .font(.footnote)
        } else if model.pickingDeadline == taskID {
            VStack(alignment: .leading, spacing: 8) {
                Text(DocumentStrings.deadline)
                Text(DocumentStrings.deadlinePickHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                DatePicker(
                    DocumentStrings.deadline,
                    // Shows today; only a tapped day is stored.
                    selection: Binding(
                        get: { model.today.date(in: .current) },
                        set: { model.pickDeadline(CalendarDate($0, in: .current), for: taskID) }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .accessibilityHint(DocumentStrings.deadlineHint)
                HStack {
                    Button(DocumentStrings.deadlinePickToday) { model.pickDeadline(model.today, for: taskID) }
                    Spacer()
                    Button(DocumentStrings.deadlinePickCancel) { model.cancelPickingDeadline() }
                }
                .buttonStyle(.borderless)
            }
        } else {
            LabeledContent(DocumentStrings.deadline) {
                Button(DocumentStrings.addDate) { model.startPickingDeadline(for: taskID) }
            }
            .accessibilityHint(DocumentStrings.deadlineHint)
        }
    }
}

/// "Deze taak verwijderen?" before a task with a description or termijn goes. A question, like "Ontkoppelen" and
/// throwing a scan away; it closes when the app leaves the foreground (`ReviewModel.sceneDidChange`).
struct RemoveTaskQuestion: ViewModifier {
    @Bindable var model: ReviewModel
    let taskID: UUID

    func body(content: Content) -> some View {
        content.confirmationDialog(
            DocumentStrings.removeTaskTitle,
            isPresented: Binding(
                get: { model.taskAskedToRemove == taskID },
                set: { if !$0 { model.taskAskedToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(DocumentStrings.removeTaskConfirm, role: .destructive) { model.confirmRemoveTask() }
            Button(DocumentStrings.removeTaskKeep, role: .cancel) { model.taskAskedToRemove = nil }
        } message: {
            Text(DocumentStrings.removeTaskMessage)
        }
    }
}
#endif
