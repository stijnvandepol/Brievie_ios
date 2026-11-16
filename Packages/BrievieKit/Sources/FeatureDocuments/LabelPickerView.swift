#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// Every label of the workspace to tick. Labels are made in the web interface, not here.
struct LabelPickerView: View {
    let labels: [DocumentLabel]
    @Binding var selection: Set<UUID>
    let close: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(labels) { label in
                        PickerRow(isSelected: selection.contains(label.id)) {
                            selection.formSymmetricDifference([label.id])
                        } title: {
                            LabelChip(name: label.name, colorKey: label.colorKey)
                        }
                    }
                } footer: {
                    Text(DocumentStrings.labelsInWeb)
                }
            }
            .navigationTitle(DocumentStrings.pickLabels)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(DocumentStrings.pickerDone, action: close)
                }
            }
        }
    }
}
#endif
