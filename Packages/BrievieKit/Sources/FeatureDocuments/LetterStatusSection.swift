#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// The letter's status under its title and, for a member, "Brief afhandelen" with its confirmation sheet.
struct LetterStatusSection: View {
    @Bindable var model: ConfirmedDocumentModel

    var body: some View {
        if model.letterBadge != nil || model.canHandle {
            Section {
                if let badge = model.letterBadge {
                    LetterStatusBadge(badge: badge)
                }
                if model.canHandle {
                    Button(DocumentStrings.handleButton) { model.startHandling() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(item: $model.handleSheet) { sheet in
                HandleLetterSheet(
                    sheet: sheet, error: model.handleError,
                    handle: { paid in Task { await model.handle(paymentsConfirmed: paid) } },
                    cancel: { model.closeHandleSheet() }
                )
            }
        }
    }
}

/// "Brief afhandelen?": the tasks that will be ticked off, and for a payment the required tick.
struct HandleLetterSheet: View {
    let sheet: ConfirmedDocumentModel.HandleSheet
    let error: String?
    let handle: (Bool) -> Void
    let cancel: () -> Void
    @State private var paid = false

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Section { ErrorBanner(error) }
                }
                Section {
                    if sheet.taskTitles.isEmpty {
                        Text(DocumentStrings.handleNoTasks).foregroundStyle(.secondary)
                    }
                    ForEach(Array(sheet.taskTitles.enumerated()), id: \.offset) { _, title in
                        Label(title, systemImage: "checkmark.circle")
                    }
                } header: {
                    Text(DocumentStrings.handleTasks).textCase(nil)
                }
                if sheet.needsPayment {
                    Section {
                        Toggle(DocumentStrings.handlePayment, isOn: $paid)
                    }
                }
            }
            .navigationTitle(DocumentStrings.handleTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(DocumentStrings.myTasksSetDateCancel, action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(DocumentStrings.handleConfirm) { handle(paid) }
                        .disabled(sheet.needsPayment && !paid)
                }
            }
        }
        // A new set of tasks (409 `tasks_changed`) asks for the tick again.
        .onChange(of: sheet) { paid = false }
    }
}
#endif
