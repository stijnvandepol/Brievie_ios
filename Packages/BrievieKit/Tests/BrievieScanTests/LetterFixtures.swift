import Foundation
import Testing

/// Made-up Dutch letters (texts in `Fixtures/letters/<key>-<page>.txt`) with the facts that must survive a
/// scan. All names, numbers, addresses and amounts are invented; 111222333 is a made-up number that passes
/// the BSN check on purpose. Real letters never go in this repository.
struct LetterFixture: Sendable, CustomTestStringConvertible {
    enum Kind: String, Sendable {
        case sender, date, amount, deadline, addressee
    }

    struct Fact: Sendable {
        let kind: Kind
        /// As printed; compared without case, accents and line breaks.
        let text: String
        /// 1-based page the fact is on.
        var page = 1
    }

    let key: String
    let pageCount: Int
    let facts: [Fact]
    let style: ScanStyle

    var testDescription: String { key }

    func text(ofPage page: Int) throws -> String {
        guard
            let url = Bundle.module.url(
                forResource: "\(key)-\(page)", withExtension: "txt", subdirectory: "Fixtures/letters"
            )
        else { throw CocoaError(.fileNoSuchFile) }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

extension LetterFixture {
    private static func facts(
        _ sender: String, _ date: String, amount: String? = nil, deadline: String? = nil, deadlinePage: Int = 1,
        addressee: String
    ) -> [Fact] {
        var facts = [Fact(kind: .sender, text: sender), Fact(kind: .date, text: date)]
        if let amount { facts.append(Fact(kind: .amount, text: amount)) }
        if let deadline { facts.append(Fact(kind: .deadline, text: deadline, page: deadlinePage)) }
        facts.append(Fact(kind: .addressee, text: addressee))
        return facts
    }

    /// Each letter with its own way of being spoiled, so together they cover every kind of damage.
    static let all: [LetterFixture] = [
        LetterFixture(
            key: "belasting", pageCount: 1,
            facts: facts(
                "Belastingdienst", "12 november 2026", amount: "1.248,00", deadline: "uiterlijk 31 december 2026",
                addressee: "S.T.J. van de Pol"
            ),
            style: ScanStyle()
        ),
        LetterFixture(
            key: "energie", pageCount: 1,
            facts: facts(
                "Vattenfall Klantenservice", "9 november 2026", amount: "186,40", deadline: "vóór 3 december 2026",
                addressee: "M. de Vries"
            ),
            style: ScanStyle(skew: 3, softness: 0.55)
        ),
        LetterFixture(
            key: "paspoort", pageCount: 1,
            facts: facts(
                "Gemeente Venray", "5 november 2026", amount: "83,87", deadline: "tot en met 14 februari 2027",
                addressee: "S.T.J. van de Pol"
            ),
            style: ScanStyle(lowContrast: true, shadow: true)
        ),
        LetterFixture(
            key: "zorgpolis", pageCount: 1,
            facts: facts(
                "CZ Zorgverzekeringen", "14 november 2026", amount: "158,95",
                deadline: "tot en met 31 december 2026", addressee: "M. de Vries"
            ),
            style: ScanStyle(font: "Times New Roman", skew: -2, noise: true)
        ),
        LetterFixture(
            key: "incasso", pageCount: 1,
            facts: facts(
                "Flanderijn Incasso", "10 november 2026", amount: "99,90",
                deadline: "binnen 14 dagen na dagtekening", addressee: "S.T.J. van de Pol"
            ),
            style: ScanStyle(font: "Courier", softness: 0.6, shadow: true)
        ),
        LetterFixture(
            key: "verkeersboete", pageCount: 1,
            facts: facts(
                "Centraal Justitieel Incassobureau", "3 november 2026", amount: "96,00",
                deadline: "vóór 15 december 2026", addressee: "S.T.J. van de Pol"
            ),
            style: ScanStyle(skew: 4, lowContrast: true)
        ),
        LetterFixture(
            key: "tandarts", pageCount: 1,
            facts: facts(
                "Tandartspraktijk De Peel", "16 november 2026", deadline: "2 december 2026 om 10:15",
                addressee: "M. de Vries"
            ),
            style: ScanStyle(font: "Georgia", shadow: true, noise: true)
        ),
        LetterFixture(
            key: "reclame", pageCount: 1,
            facts: facts(
                "Glasvezel Buitenaf", "November 2026", amount: "47,50", deadline: "zolang de voorraad strekt",
                addressee: "Aan de bewoners van"
            ),
            style: ScanStyle(skew: -3, softness: 0.6, lowContrast: true)
        ),
        LetterFixture(
            key: "vorige_bewoner", pageCount: 1,
            facts: facts(
                "Rabobank", "11 november 2026", amount: "3,95", deadline: "Per 1 januari 2027",
                addressee: "P. Bakker"
            ),
            style: ScanStyle(font: "Times New Roman", softness: 0.5)
        ),
        LetterFixture(
            key: "jaaropgaaf", pageCount: 1,
            facts: facts(
                "Stichting Voorbeeldzorg", "2 november 2026", amount: "2.348,60", addressee: "S.T.J. van de Pol"
            ),
            style: ScanStyle(skew: 2, shadow: true, noise: true)
        ),
        LetterFixture(
            key: "injectie", pageCount: 1,
            facts: facts("Voordeelclub Nederland", "13 november 2026", addressee: "S.T.J. van de Pol"),
            style: ScanStyle(lowContrast: true, noise: true)
        ),
        LetterFixture(
            key: "huurverhoging", pageCount: 2,
            facts: facts(
                "Wonen Limburg", "6 november 2026", amount: "772,61", deadline: "vóór 1 januari 2027",
                deadlinePage: 2, addressee: "S.T.J. van de Pol en mevrouw M. de Vries"
            ),
            style: ScanStyle(skew: -1.5, softness: 0.65, shadow: true)
        )
    ]
}
