import BrievieCore
import Foundation

// The trash in the post list: whether the server has one, the undo notice after deleting, the Prullenbak screen.
extension DocumentsModel {
    /// The notice after a letter went to the trash. No timer: it goes on "Sluiten", on a scope change, or once undone.
    public struct UndoNotice: Equatable, Sendable {
        public let documentID: UUID
        public let message: String
        /// Why "Ongedaan maken" did not work; `nil` before a try.
        public var failure: String?
    }

    /// A whole load asks for the trash once: there is no other way to tell a server without one (it answers 404
    /// without a Brievie code). `nil` keeps what is known: a failure says nothing about the endpoint.
    nonisolated static func probeTrash(_ documents: WorkspaceDocuments) async -> Bool? {
        do {
            _ = try await documents.trashList()
            return true
        } catch .notSupported {
            return false
        } catch {
            return nil
        }
    }

    /// The letter screen put `id` in the trash: offer the undo and load the list without it.
    public func didTrash(_ id: UUID) async {
        undo = UndoNotice(documentID: id, message: DocumentStrings.undoTrashed)
        await load()
    }

    /// "Ongedaan maken": the letter comes back and opens again. A failure stays on the notice.
    public func undoTrash() async {
        guard let notice = undo, !isUndoing else { return }
        isUndoing = true
        defer { isUndoing = false }
        do {
            _ = try await documents.restore(notice.documentID)
            if undo?.documentID == notice.documentID { undo = nil }
            await load()
            openedDocument = notice.documentID
        } catch .revoked {
            onRevoked()
        } catch .missingPairing {
            onMissingPairing()
        } catch .cancelled {
            return
        } catch {
            guard undo?.documentID == notice.documentID else { return }
            undo?.failure = error == .notFound ? DocumentStrings.undoFailed : Self.message(for: error)
        }
    }

    public func closeUndo() {
        undo = nil
    }

    /// The Prullenbak screen of this workspace; a restore loads the post list again.
    public func makeTrashModel() -> TrashModel {
        TrashModel(
            documents: documents, canRestore: canScan,
            onRestored: { [weak self] in
                guard let self else { return }
                Task { await self.load() }
            },
            onRevoked: onRevoked, onMissingPairing: onMissingPairing
        )
    }
}
