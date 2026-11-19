import Foundation
import Observation

/// The letter on the whole screen: which page is shown, as the image or as its text, and whether the image is
/// zoomed in. Pages and texts stay with `ReviewModel`; this holds only where the reader is.
@MainActor
@Observable
public final class LetterReaderModel {
    public enum Mode: Hashable, Sendable {
        /// The image of the page, to zoom in on.
        case page
        /// The recognised text of every page, as real text (Dynamic Type, selection, VoiceOver).
        case text
    }

    public let pageCount: Int
    /// The page shown, 1 through `pageCount`.
    public private(set) var page: Int
    public var mode: Mode = .page {
        didSet { if mode != oldValue { isZoomed = false } }
    }
    /// The shown page is zoomed in: swiping pans the image instead of turning the page.
    public private(set) var isZoomed = false

    public init(pageCount: Int, startPage: Int) {
        self.pageCount = max(pageCount, 1)
        page = min(max(startPage, 1), max(pageCount, 1))
    }

    /// "Pagina 2 van 3".
    public var pageLabel: String { String(format: DocumentStrings.pageFormat, page, pageCount) }
    public var hasPrevious: Bool { page > 1 }
    public var hasNext: Bool { page < pageCount }

    /// Shows `page` (kept within the letter); another page starts at its normal size.
    public func show(page: Int) {
        let page = min(max(page, 1), pageCount)
        guard page != self.page else { return }
        self.page = page
        isZoomed = false
    }

    public func next() { show(page: page + 1) }
    public func previous() { show(page: page - 1) }

    /// The image view reports a zoom made with a pinch or a double tap; only the image can be zoomed.
    public func zoomDidChange(_ zoomed: Bool) {
        guard mode == .page else { return }
        isZoomed = zoomed
    }

    /// The text of 1-based `page`, or `nil` when the app has none for it (not recognised, or only blank).
    public nonisolated static func text(ofPage page: Int, in texts: [String]) -> String? {
        guard texts.indices.contains(page - 1) else { return nil }
        let text = texts[page - 1]
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}
