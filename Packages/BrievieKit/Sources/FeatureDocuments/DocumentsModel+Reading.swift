import BrievieCore
import Foundation

// "Ongelezen" (navigation design, section 5): the dot and bold title in "Mijn post" and "Alle post", "Markeer als
// gelezen / ongelezen", "Alles gelezen", and a letter that was opened. Never in the Inbox.
extension DocumentsModel.Scope {
    /// The lists that show what is unread: not the Inbox (a to-do list for whoever sorts, ruling N4).
    var showsUnread: Bool {
        self != .inbox
    }
}

extension DocumentsModel {
    /// The list offers "Markeer als gelezen / ongelezen" and "Alles gelezen": the server knows read marks and this
    /// list shows them.
    public var offersReading: Bool {
        tracksReading && scope.showsUnread
    }

    /// "Alles gelezen" has something to do: a letter on screen is unread.
    public var hasUnreadRows: Bool {
        rows.contains(where: \.isUnread)
    }

    /// The letter's screen appeared (it called `markDocumentRead` itself): the row is read at once, the menu's
    /// numbers follow.
    public func didRead(_ id: UUID) {
        guard setUnread(false, for: [id]) else { return }
        onListChanged()
    }

    /// "Markeer als gelezen" on one row.
    public func markRead(_ id: UUID) async {
        await mark([id], unread: false)
    }

    /// "Markeer als ongelezen" on one row.
    public func markUnread(_ id: UUID) async {
        await mark([id], unread: true)
    }

    /// "Alles gelezen": the unread letters on screen (at most the 200 the list holds).
    public func markAllRead() async {
        let ids = rows.filter(\.isUnread).compactMap(\.documentID)
        guard !ids.isEmpty else { return }
        await mark(ids, unread: false)
    }

    /// Shows the change at once and tells the server; a failure puts the rows back and says why.
    private func mark(_ ids: [UUID], unread: Bool) async {
        guard offersReading else { return }
        let before = serverDocuments
        setUnread(unread, for: ids)
        readingError = nil
        do {
            if unread, let id = ids.first {
                try await documents.markUnread(id)
            } else if ids.count == 1, let id = ids.first {
                try await documents.markRead(id)
            } else {
                _ = try await documents.markRead(ids)
            }
            onListChanged()
        } catch {
            serverDocuments = before
            rebuild()
            switch error {
            case .revoked: onRevoked()
            case .missingPairing: onMissingPairing()
            case .cancelled: break
            case .notSupported:
                tracksReading = false
            case .notFound:
                // The letter is gone (trashed elsewhere): the list catches up.
                await load()
            default:
                readingError = Self.message(for: error)
            }
        }
    }

    /// `true` when a letter of `ids` changed.
    @discardableResult
    private func setUnread(_ unread: Bool, for ids: [UUID]) -> Bool {
        let wanted = Set(ids)
        var changed = false
        for index in serverDocuments.indices where wanted.contains(serverDocuments[index].id) {
            guard serverDocuments[index].isUnread != unread else { continue }
            serverDocuments[index].isUnread = unread
            changed = true
        }
        if changed {
            // In "Alleen ongelezen" a read letter leaves the list.
            if scope == .myPostUnread, !unread { serverDocuments.removeAll { wanted.contains($0.id) } }
            rebuild()
        }
        return changed
    }
}
