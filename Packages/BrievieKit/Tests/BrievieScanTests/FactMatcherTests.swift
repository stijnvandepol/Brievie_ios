import Testing

/// The tolerance of the scan-quality check, pinned. Pure logic: runs everywhere.
@Suite struct FactMatcherTests {
    private func fact(_ kind: LetterFixture.Kind, _ text: String) -> LetterFixture.Fact {
        LetterFixture.Fact(kind: kind, text: text)
    }

    @Test(arguments: [
        ("Flanderijn Incasso", "'landerijn Incasso en Gerechtsdeurwaarders"),  // a lost first letter
        ("CZ Zorgverzekeringen", "CZ. Zorgverzekcringen"),  // one wrong letter, a stray full stop
        ("J.A. de Wilde", "De heer J.A. de Wi1de"),  // l read as 1
        ("Aan de bewoners van", "AAN DE  BEWONERS\nVAN")  // case and line breaks
    ])
    func namesSurviveTheUsualOCRSlips(expected: String, read: String) {
        #expect(FactMatcher.found(fact(.sender, expected), in: read))
    }

    @Test func aDifferentNameDoesNotPass() {
        #expect(!FactMatcher.found(fact(.sender, "Belastingdienst"), in: "Voordeelclub Nederland"))
        #expect(!FactMatcher.found(fact(.addressee, "M. de Vries"), in: "De heer P. Bakker"))
    }

    @Test(arguments: [
        ("1.248,00", "bedrag is € 1.246,00."),
        ("1.248,00", "bedrag is € 1.248,0O."),
        ("186,40", "u € 18640"),
        ("12 november 2026", "Datum: 12 november 2028"),
        ("vóór 3 december 2026", "voor 8 december 2026")
    ])
    func amountsDatesAndPhrasesWithNumbersStayExact(expected: String, read: String) {
        let kind: LetterFixture.Kind = expected.contains("v") ? .deadline : .amount
        #expect(!FactMatcher.found(fact(kind, expected), in: read))
    }

    @Test func accentsAndCaseDoNotCountForDates() {
        #expect(FactMatcher.found(fact(.deadline, "vóór 3 december 2026"), in: "VOOR 3 December 2026 over"))
    }

    @Test func readingOrderIsMeasuredOnTheLines() {
        let source = "Eerste regel van de brief\nTweede regel van de brief\nDerde regel van de brief"
        #expect(ScanQualityTests.orderShare(of: source, against: source) == 1)
        let swapped = "Derde regel van de brief\nTweede regel van de brief\nEerste regel van de brief"
        #expect(ScanQualityTests.orderShare(of: swapped, against: source) < 0.5)
    }
}
