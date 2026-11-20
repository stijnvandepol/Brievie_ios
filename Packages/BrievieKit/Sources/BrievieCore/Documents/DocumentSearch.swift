import Foundation

/// One search in the letters of a workspace (`searchDocuments`). The term travels in a POST body, never in a URL,
/// and is never logged. The server removes a BSN from it before it searches.
public struct DocumentSearchQuery: Equatable, Sendable {
    /// The server refuses a longer term (422).
    public static let maxLength = 200
    /// The server's page size for the app, as in the web.
    public static let pageSize = 30

    public let text: String
    /// Where the page starts: 0, or the `nextOffset` of the page before.
    public let offset: Int

    public init(text: String, offset: Int = 0) {
        self.text = text
        self.offset = offset
    }
}

/// A piece of a hit's fragment; `isHit` marks the words that matched.
public struct SnippetPart: Equatable, Sendable {
    public let text: String
    public let isHit: Bool

    public init(text: String, isHit: Bool) {
        self.text = text
        self.isHit = isHit
    }
}

/// A letter that matched: its list entry and the fragment where the words were found (empty when the server has
/// none, for example a match on a label).
public struct DocumentSearchHit: Equatable, Sendable {
    public let document: DocumentSummary
    public let snippet: [SnippetPart]

    public init(document: DocumentSummary, snippet: [SnippetPart] = []) {
        self.document = document
        self.snippet = snippet
    }
}

/// One page of results, best first.
public struct DocumentSearchPage: Equatable, Sendable {
    public let hits: [DocumentSearchHit]
    /// `nil` on the last page.
    public let nextOffset: Int?
    /// Nothing matched exactly: these letters have similar words.
    public let isFuzzy: Bool
    /// The server took a BSN out of the term before it searched.
    public let bsnRemoved: Bool

    public init(hits: [DocumentSearchHit], nextOffset: Int? = nil, isFuzzy: Bool = false, bsnRemoved: Bool = false) {
        self.hits = hits
        self.nextOffset = nextOffset
        self.isFuzzy = isFuzzy
        self.bsnRemoved = bsnRemoved
    }
}
