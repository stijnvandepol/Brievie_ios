#if os(iOS)
import BrievieCore
import SwiftUI

/// A task's termijn. "Datum toevoegen" opens a calendar on today, but the termijn stays empty until the user taps
/// a day or "Vandaag": a tap that only looks never sets one (seen in the simulator, 20-11-2026).
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

    func body(content: Content) -> some View {
        content.confirmationDialog(
            DocumentStrings.removeTaskTitle,
            isPresented: Binding(
                get: { model.taskAskedToRemove != nil },
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
