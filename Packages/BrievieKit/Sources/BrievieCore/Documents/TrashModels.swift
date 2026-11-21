import Foundation

/// A letter in the trash: what the list shows of it, who put it there, and when the server erases it.
public struct TrashedDocument: Identifiable, Equatable, Sendable {
    public let summary: DocumentSummary
    public let trashedAt: Date
    /// Empty when Brievie itself trashed the letter (a merge), or for a server that does not say.
    public let trashedByName: String
    /// When the server erases the letter for good. Always the server's value: never computed from `trashedAt`.
    public let purgeAfter: Date

    public var id: UUID { summary.id }

    public init(summary: DocumentSummary, trashedAt: Date, trashedByName: String, purgeAfter: Date) {
        self.summary = summary
        self.trashedAt = trashedAt
        self.trashedByName = trashedByName
        self.purgeAfter = purgeAfter
    }
}

/// The trash of a workspace as the server lists it (newest first, capped by the server).
public struct TrashList: Equatable, Sendable {
    public let items: [TrashedDocument]
    /// How many days a letter stays in the trash, for the explanation.
    public let retentionDays: Int
    /// How many letters the trash holds; more than `items` when the server capped the list.
    public let total: Int

    /// `total` is at least the number of items: a server without the field sends 0.
    public init(items: [TrashedDocument], retentionDays: Int = 30, total: Int = 0) {
        self.items = items
        self.retentionDays = retentionDays
        self.total = max(total, items.count)
    }
}
