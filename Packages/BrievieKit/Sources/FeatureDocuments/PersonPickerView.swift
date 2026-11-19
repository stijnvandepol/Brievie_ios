#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// Every person of the workspace to tick, and "Nieuwe persoon". An archived person is only listed while
/// chosen, so the letter can be taken off their name.
struct PersonPickerView: View {
    let persons: [Person]
    @Binding var selection: Set<UUID>
    let error: String?
    /// Adds a person and puts the letter on their name; true when it worked.
    let onCreate: (String) async -> Bool
    let close: () -> Void

    @State private var newName = ""
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(persons.filter { !$0.isArchived || selection.contains($0.id) }) { person in
                        PickerRow(title: person.displayName, isSelected: selection.contains(person.id)) {
                            selection.formSymmetricDifference([person.id])
                        }
                    }
                } footer: {
                    // A person is not a member: the same sentence as the web's Personen page.
                    Text(DocumentStrings.personsExplained)
                }
                Section {
                    TextField(DocumentStrings.newPersonName, text: $newName)
                        .textContentType(.name)
                        .submitLabel(.done)
                        .onSubmit(create)
                    Button(DocumentStrings.newPersonAdd, action: create)
                        .disabled(isCreating || newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let error {
                        ErrorBanner(error)
                    }
                } header: {
                    Text(DocumentStrings.newPerson)
                }
            }
            .navigationTitle(DocumentStrings.pickPersons)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(DocumentStrings.pickerDone, action: close)
                }
            }
        }
    }

    private func create() {
        guard !isCreating else { return }
        isCreating = true
        Task {
            if await onCreate(newName) { newName = "" }
            isCreating = false
        }
    }
}

/// A row to tick: the title with a check mark when selected; VoiceOver hears "geselecteerd".
struct PickerRow<Title: View>: View {
    let isSelected: Bool
    let toggle: () -> Void
    @ViewBuilder let title: () -> Title

    init(isSelected: Bool, toggle: @escaping () -> Void, @ViewBuilder title: @escaping () -> Title) {
        self.isSelected = isSelected
        self.toggle = toggle
        self.title = title
    }

    var body: some View {
        Button(action: toggle) {
            HStack {
                title()
                    .foregroundStyle(Color.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension PickerRow where Title == Text {
    init(title: String, isSelected: Bool, toggle: @escaping () -> Void) {
        self.init(isSelected: isSelected, toggle: toggle) { Text(title) }
    }
}
#endif
