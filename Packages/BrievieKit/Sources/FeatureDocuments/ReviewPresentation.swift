import Foundation

/// The list a sheet shows to choose persons or labels from.
public enum OrganisePicker: Identifiable, Sendable {
    case persons, labels
    public var id: Self { self }
}

/// The quote whose place in the letter is being shown.
public struct SourceQuote: Identifiable, Equatable, Sendable {
    public let text: String
    public var id: String { text }
}

extension ReviewModel {
    /// Opens the letter on the whole screen at `page`; nothing when there are no pages to show. The reader is
    /// pushed, not a sheet: it stays under the lock screen, so it does not close when the app leaves the
    /// foreground.
    public func openReader(at page: Int) {
        guard pageCount > 0 else { return }
        reader = LetterReaderModel(pageCount: pageCount, startPage: page)
    }

    public func closeReader() {
        reader = nil
    }
}
