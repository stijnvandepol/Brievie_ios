import BrievieCore
import Foundation
import Observation

/// Where the letter reader gets its pages and texts: the review of one letter, or one letter of a duplicate pair.
@MainActor
protocol LetterPageSource: AnyObject, Observable {
    /// Page images by 1-based page number.
    var pages: [Int: Data] { get }
    var pageTexts: [String] { get }
    /// "Deze brief heeft 80 pagina's. Je ziet hier alleen de eerste 50."; `nil` when nothing is left out.
    var missingPagesNote: String? { get }
    func loadPage(_ index: Int) async
    func closeReader()
}

extension ReviewModel: LetterPageSource {}

/// One letter of a duplicate pair on the whole screen: its pages (the first one already loaded by the compare
/// screen) and its text. In memory only.
@MainActor
@Observable
public final class DuplicateLetterReader {
    public let documentID: UUID
    public let reader: LetterReaderModel
    public private(set) var pages: [Int: Data]
    public let pageTexts: [String]
    public let missingPagesNote: String?

    private let pageCount: Int
    private let documents: WorkspaceDocuments
    private let onClose: @MainActor () -> Void
    private let onRevoked: @MainActor () -> Void
    private let onMissingPairing: @MainActor () -> Void
    @ObservationIgnored private var loadingPages: Set<Int> = []

    init(
        documentID: UUID, pageCount: Int, pageTexts: [String], firstPage: Data?, documents: WorkspaceDocuments,
        onClose: @escaping @MainActor () -> Void, onRevoked: @escaping @MainActor () -> Void,
        onMissingPairing: @escaping @MainActor () -> Void
    ) {
        self.documentID = documentID
        let total = max(pageCount, pageTexts.count)
        self.pageCount = min(max(pageCount, 1), ReviewModel.maxPages)
        self.pageTexts = Array(pageTexts.prefix(ReviewModel.maxPages))
        missingPagesNote = total > ReviewModel.maxPages
            ? String(format: DocumentStrings.missingPagesFormat, total, ReviewModel.maxPages) : nil
        pages = firstPage.map { [1: $0] } ?? [:]
        reader = LetterReaderModel(pageCount: self.pageCount, startPage: 1)
        self.documents = documents
        self.onClose = onClose
        self.onRevoked = onRevoked
        self.onMissingPairing = onMissingPairing
    }

    public func loadPage(_ index: Int) async {
        guard (1...pageCount).contains(index), pages[index] == nil, !loadingPages.contains(index) else { return }
        loadingPages.insert(index)
        defer { loadingPages.remove(index) }
        do {
            pages[index] = try await documents.pageImage(documentID, index: index)
        } catch .revoked {
            onRevoked()
        } catch .missingPairing {
            onMissingPairing()
        } catch {
            // The page stays a placeholder.
        }
    }

    public func closeReader() {
        onClose()
    }
}

extension DuplicateLetterReader: LetterPageSource {}
