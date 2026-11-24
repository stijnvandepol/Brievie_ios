import BrievieCore
import Foundation

extension DocumentsModel {
    /// The letters with one label, as a list of their own (Meer, Labels): the same workspace, its own scope.
    public func makeLabelModel(_ label: UUID) -> DocumentsModel {
        let model = DocumentsModel(
            documents: documents, scope: .label(label), uploads: uploads, canScan: canScan, camera: camera,
            openSettings: settingsOpener, onRevoked: onRevoked, onMissingPairing: onMissingPairing
        )
        model.tracksReading = tracksReading
        model.onTasksChanged = onTasksChanged
        model.onListChanged = onListChanged
        return model
    }
}
