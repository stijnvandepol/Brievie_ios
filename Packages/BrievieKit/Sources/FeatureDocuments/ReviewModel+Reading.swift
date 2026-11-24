import BrievieCore
import Foundation

extension ReviewModel {
    /// The letter's screen appeared: once per opening, the server hears that the member opened it (not on a plain
    /// load, which is also a refresh). Whether that counts for "Blijft liggen" is the server's matter.
    func markReadOnce() async {
        guard !askedToMarkRead else { return }
        askedToMarkRead = true
        do {
            try await documents.markRead(documentID)
            onRead?()
        } catch {
            // An older server has no read marks, and a failure here is not worth a message: the letter is open.
            handle(error) { _ in }
        }
    }
}
