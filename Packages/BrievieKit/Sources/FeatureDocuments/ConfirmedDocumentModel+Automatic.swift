import BrievieCore
import Foundation

// What the AI did by itself on a confirmed letter (the web's "Automatisch door AI").
extension ConfirmedDocumentModel {
    /// The AI confirmed the letter itself; nobody checked it.
    public var isConfirmedByAI: Bool { detail.summary.confirmedByAI }

    /// "Automatisch toegevoegd: Wonen" under the labels: those on the letter that the AI or a rule put there.
    public var automaticLabelsNote: String? {
        let automatic = Set(detail.summary.autoLabelIDs)
        let names = labels.filter { automatic.contains($0.id) && organise.labelIDs.contains($0.id) }.map(\.name)
        return names.isEmpty ? nil : String(format: DocumentStrings.automaticAddedFormat, names.joined(separator: ", "))
    }

    /// The same under "Op naam van".
    public var automaticAddresseesNote: String? {
        let automatic = Set(detail.summary.autoAddresseeIDs)
        let names = persons.filter { automatic.contains($0.id) && organise.addresseeIDs.contains($0.id) }
            .map(\.displayName)
        return names.isEmpty ? nil : String(format: DocumentStrings.automaticAddedFormat, names.joined(separator: ", "))
    }
}
