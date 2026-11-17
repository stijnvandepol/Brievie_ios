import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// A page count from the server is a number the screen loops over: a broken or hostile server must not make it
/// build a billion pages, or crash on a negative count.
@MainActor
@Suite struct ReviewBoundsTests {
    private let harness = ReviewHarness()

    private nonisolated static func detail(id: UUID, pageCount: Int, pageTexts: [String]? = nil) -> DocumentDetail {
        let base = DocumentFixtures.detail(id: id)
        let summary = base.summary
        return DocumentDetail(
            summary: DocumentSummary(
                id: summary.id, clientID: summary.clientID, status: summary.status, pageCount: pageCount,
                createdAt: summary.createdAt, sender: summary.sender, documentType: summary.documentType,
                letterDate: summary.letterDate, inboxState: summary.inboxState
            ),
            failureCode: base.failureCode, summaryText: base.summaryText, summaryByAI: base.summaryByAI,
            pageTexts: pageTexts ?? base.pageTexts, proposals: base.proposals, tasks: base.tasks
        )
    }

    @Test func aHugePageCountIsCappedAtTheMaximum() async throws {
        harness.answer { id in Self.detail(id: id, pageCount: 1_000_000_000) }
        let model = try harness.model()

        await model.load()

        #expect(model.pageCount == ReviewModel.maxPages)
    }

    @Test func aNegativePageCountShowsNoPages() async throws {
        harness.answer { id in Self.detail(id: id, pageCount: -5) }
        let model = try harness.model()

        await model.load()

        #expect(model.pageCount == 0)
    }

    @Test func aPageAboveTheMaximumIsNeverRequested() async throws {
        harness.answer { id in Self.detail(id: id, pageCount: 1_000_000_000) }
        let model = try harness.model()
        await model.load()

        await model.loadPage(ReviewModel.maxPages + 1)
        await model.loadPage(0)

        let pageCalls = harness.server.calls.filter { if case .page = $0 { true } else { false } }
        #expect(pageCalls.isEmpty)
    }

    @Test func theMaximumIsAboveWhatTheServerAcceptsByDefault() {
        // The host refuses more than 30 pages per letter (`BRIEVIE_MAX_PAGES`, default 30).
        #expect(ReviewModel.maxPages >= UploadLimits.server.maxPages)
    }

    @Test func aLetterWithMorePagesThanShownSaysSo() async throws {
        harness.answer { id in Self.detail(id: id, pageCount: 80) }
        let model = try harness.model()

        await model.load()

        #expect(model.missingPagesNote == "Deze brief heeft 80 pagina's. Je ziet hier alleen de eerste 50.")
    }

    @Test func aLetterWithinTheMaximumHasNoNote() async throws {
        harness.answer { id in Self.detail(id: id, pageCount: 3) }
        let model = try harness.model()

        await model.load()

        #expect(model.missingPagesNote == nil)
    }

    @Test func thePageTextsAreCappedTheSameWay() async throws {
        let texts = (1...80).map { "Pagina \($0)" }
        harness.answer { id in Self.detail(id: id, pageCount: 80, pageTexts: texts) }
        let model = try harness.model()

        await model.load()

        #expect(model.pageTexts.count == ReviewModel.maxPages)
        #expect(model.pageTexts.last == "Pagina 50")
    }
}
