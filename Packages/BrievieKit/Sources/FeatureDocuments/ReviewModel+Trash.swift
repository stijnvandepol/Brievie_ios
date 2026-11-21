import BrievieCore
import Foundation

// "Verwijderen": the letter goes to the trash, after a question.
extension ReviewModel {
    /// A member or admin, on a server with a trash, for a letter to check or a confirmed one; not while saving.
    public var canTrash: Bool {
        canEdit && trashAvailable && (state == .review || state == .done) && !isSaving
    }

    /// "Verwijderen" asks first; nothing is sent yet.
    public func askToTrash() {
        guard canTrash else { return }
        asksToTrash = true
    }

    /// "Naar de prullenbak": one request, also when tapped twice. On success the screen closes and the post list
    /// offers the undo.
    public func trash() async {
        asksToTrash = false
        guard canTrash else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            _ = try await documents.trash(documentID)
            state = .trashed
            onTrashed?(documentID)
        } catch {
            handle(error) { saveError = DocumentsModel.message(for: $0) }
        }
    }
}
