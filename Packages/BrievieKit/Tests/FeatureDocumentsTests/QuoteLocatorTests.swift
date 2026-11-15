@testable import FeatureDocuments
import Foundation
import Testing

@Suite struct QuoteLocatorTests {
    private func found(_ quote: String, in text: String) -> [String] {
        QuoteLocator.ranges(of: quote, in: text).map { String(text[$0]) }
    }

    @Test func findsTheQuoteDespiteDiacriticsCaseAndLineBreaks() {
        let text = "U moet betalen voor 1  december\n2026. Daarna volgt een boete."

        #expect(found("vóór 1 december 2026", in: text) == ["voor 1  december\n2026"])
        #expect(found("VOOR 1 DECEMBER", in: text) == ["voor 1  december"])
    }

    @Test func findsEveryOccurrence() {
        #expect(found("CAK", in: "Het CAK schrijft. Bel het cak.") == ["CAK", "cak"])
    }

    @Test func accentedTextKeepsItsOwnCharacters() {
        #expect(found("een", in: "Dat is één brief") == ["één"])
    }

    @Test(arguments: ["", "   ", "staat er niet"])
    func nothingToFindGivesNoRanges(quote: String) {
        #expect(found(quote, in: "Een brief van de gemeente.").isEmpty)
    }

    @Test func emptyTextGivesNoRanges() {
        #expect(found("iets", in: "").isEmpty)
    }
}
