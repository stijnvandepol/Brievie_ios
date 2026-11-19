import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// The full-screen reader: which page, which mode, whether a page is zoomed, and the text of a page.
@MainActor
@Suite struct LetterReaderTests {
    @Test func startsOnTheTappedPageWithinBounds() {
        #expect(LetterReaderModel(pageCount: 3, startPage: 2).page == 2)
        #expect(LetterReaderModel(pageCount: 3, startPage: 9).page == 3)
        #expect(LetterReaderModel(pageCount: 3, startPage: 0).page == 1)
    }

    @Test func startsInPageModeNotZoomed() {
        let reader = LetterReaderModel(pageCount: 3, startPage: 1)

        #expect(reader.mode == .page)
        #expect(!reader.isZoomed)
        #expect(reader.pageLabel == "Pagina 1 van 3")
    }

    @Test func nextAndPreviousStopAtTheEnds() {
        let reader = LetterReaderModel(pageCount: 2, startPage: 1)
        #expect(!reader.hasPrevious)
        #expect(reader.hasNext)

        reader.next()
        #expect(reader.page == 2)
        #expect(!reader.hasNext)
        reader.next()
        #expect(reader.page == 2)

        reader.previous()
        reader.previous()
        #expect(reader.page == 1)
    }

    @Test func changingThePageResetsTheZoom() {
        let reader = LetterReaderModel(pageCount: 3, startPage: 1)
        reader.zoomDidChange(true)
        #expect(reader.isZoomed)

        reader.show(page: 2)

        #expect(reader.page == 2)
        #expect(!reader.isZoomed)
    }

    @Test func showingTheSamePageKeepsTheZoom() {
        let reader = LetterReaderModel(pageCount: 3, startPage: 2)
        reader.zoomDidChange(true)

        reader.show(page: 2)

        #expect(reader.isZoomed)
    }

    @Test func showClampsToThePages() {
        let reader = LetterReaderModel(pageCount: 3, startPage: 1)

        reader.show(page: 7)
        #expect(reader.page == 3)
        reader.show(page: -1)
        #expect(reader.page == 1)
    }

    @Test func switchingToTextResetsTheZoomAndIgnoresZoomReports() {
        let reader = LetterReaderModel(pageCount: 2, startPage: 1)
        reader.zoomDidChange(true)

        reader.mode = .text
        #expect(!reader.isZoomed)
        reader.zoomDidChange(true)
        #expect(!reader.isZoomed)

        reader.mode = .page
        #expect(reader.page == 1)
    }

    @Test func textOfAPageOrNothingWhenTheAppHasNone() {
        let texts = ["Eerste pagina", "  \n ", "Derde"]

        #expect(LetterReaderModel.text(ofPage: 1, in: texts) == "Eerste pagina")
        #expect(LetterReaderModel.text(ofPage: 2, in: texts) == nil)
        #expect(LetterReaderModel.text(ofPage: 3, in: texts) == "Derde")
        #expect(LetterReaderModel.text(ofPage: 4, in: texts) == nil)
        #expect(LetterReaderModel.text(ofPage: 0, in: texts) == nil)
    }
}

/// Opening and closing the reader from the review and the confirmed letter.
@MainActor
@Suite struct ReviewReaderTests {
    private let harness = ReviewHarness()

    @Test func opensOnTheTappedPage() async throws {
        harness.answer { id in Self.detail(id: id, pages: 3) }
        let model = try harness.model()
        await model.load()

        model.openReader(at: 2)

        #expect(model.reader?.page == 2)
        #expect(model.reader?.pageCount == 3)
        model.closeReader()
        #expect(model.reader == nil)
    }

    @Test func opensOnAConfirmedLetterToo() async throws {
        harness.answer { id in DocumentFixtures.detail(id: id, status: .done) }
        let model = try harness.model()
        await model.load()

        model.openReader(at: 1)

        #expect(model.state == .done)
        #expect(model.reader?.page == 1)
        #expect(LetterReaderModel.text(ofPage: 1, in: model.pageTexts) == DocumentFixtures.letterText)
    }

    @Test func doesNotOpenWithoutPages() async throws {
        harness.answer { id in Self.detail(id: id, pages: 0) }
        let model = try harness.model()
        await model.load()

        model.openReader(at: 1)

        #expect(model.reader == nil)
    }

    @Test func staysOpenWhenTheAppLeavesTheForeground() async throws {
        let model = try harness.model()
        await model.load()
        model.openReader(at: 1)

        model.sceneDidChange(isActive: false)

        // Pushed, not a sheet: it stays under the lock screen and the privacy cover.
        #expect(model.reader != nil)
    }

    private nonisolated static func detail(id: UUID, pages: Int) -> DocumentDetail {
        let base = DocumentFixtures.detail(id: id)
        let summary = base.summary
        return DocumentDetail(
            summary: DocumentSummary(
                id: summary.id, clientID: summary.clientID, status: summary.status, pageCount: pages,
                createdAt: summary.createdAt, sender: summary.sender, documentType: summary.documentType,
                letterDate: summary.letterDate, inboxState: summary.inboxState
            ),
            failureCode: base.failureCode, summaryText: base.summaryText, summaryByAI: base.summaryByAI,
            pageTexts: Array(repeating: DocumentFixtures.letterText, count: pages), proposals: base.proposals,
            tasks: base.tasks
        )
    }
}
