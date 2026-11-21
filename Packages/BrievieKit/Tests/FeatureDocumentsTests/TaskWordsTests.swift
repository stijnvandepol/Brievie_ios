import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// The words of a task row: the server's days and reasons put into Dutch (the catalog's English is checked by
/// `EnglishCatalogTests`).
@Suite struct TaskWordsTests {
    private let dutch = Locale(identifier: "nl_NL")

    private func task(
        description: String = "Betaal de aanslag", type: String = "pay", daysLeft: Int? = nil, deadline: String? = nil,
        amount: String? = nil, sender: String = "", reason: TaskReason = .none, forNames: [String] = [],
        assignedTo: String = "", assignedBy: String = "", deadlineSource: String = "", quote: String = "",
        needsDeadline: Bool = false, term: String = "", completedAt: Date? = nil, completedBy: String = ""
    ) -> WorkspaceTask {
        WorkspaceTask(
            id: UUID(), type: type, description: description, deadline: deadline.flatMap(CalendarDate.init(iso:)),
            isDone: completedAt != nil, documentID: UUID(), sender: sender, deadlineSource: deadlineSource,
            deadlineQuote: quote, termQuote: term, needsDeadline: needsDeadline,
            amount: amount.flatMap(TaskAmount.parse(api:)), daysLeft: daysLeft, reason: reason, forNames: forNames,
            assignedToName: assignedTo, assignedByName: assignedBy, completedByName: completedBy,
            completedAt: completedAt
        )
    }

    @Test func whenWordsFollowTheServersDaysLeft() {
        #expect(TaskWords.when(task(daysLeft: 0, deadline: "2026-11-21"), locale: dutch) == "Vandaag")
        #expect(TaskWords.when(task(daysLeft: 1, deadline: "2026-11-22"), locale: dutch) == "Morgen")
        #expect(TaskWords.when(task(daysLeft: 10, deadline: "2026-12-01"), locale: dutch) == "Nog 10 dagen (1 dec)")
        #expect(TaskWords.when(task(daysLeft: -1, deadline: "2026-11-20"), locale: dutch) == "1 dag te laat (20 nov)")
        #expect(TaskWords.when(task(daysLeft: -3, deadline: "2026-11-18"), locale: dutch) == "3 dagen te laat (18 nov)")
        #expect(TaskWords.when(task(daysLeft: nil, deadline: nil), locale: dutch) == nil)
        #expect(TaskWords.when(task(daysLeft: 3, deadline: nil), locale: dutch) == nil)
    }

    @Test func lateIsAlsoInWords() {
        let late = task(daysLeft: -1, deadline: "2026-11-20")
        #expect(TaskWords.isLate(late))
        #expect(TaskWords.when(late, locale: dutch)?.contains("te laat") == true)
        #expect(!TaskWords.isLate(task(daysLeft: 0, deadline: "2026-11-21")))
        #expect(!TaskWords.isLate(task()))
    }

    @Test func groupTitlesInOrder() {
        #expect([TaskGroup.overdue, .withinWeek, .later, .noDate].compactMap(TaskWords.groupTitle)
            == ["Te laat", "Binnen 7 dagen", "Later", "Zonder datum"])
        #expect(TaskWords.groupTitle(.unknown) == nil)
        #expect(TaskWords.groupTitle(.none) == nil)
    }

    @Test func amountIsEurosInTheUsersLocale() {
        #expect(TaskWords.amount(task(amount: "1234.56"), locale: dutch) == "€\u{00A0}1.234,56")
        #expect(TaskWords.amount(task(amount: "1234.5"), locale: Locale(identifier: "en_GB")) == "€1,234.50")
        #expect(TaskWords.amount(task(amount: nil), locale: dutch) == nil)
    }

    @Test func whoseFollowsTheReason() {
        #expect(TaskWords.whose(task(reason: .assigned, assignedBy: "Anne"), me: "Stijn")
            == "Aan jou gegeven door Anne")
        #expect(TaskWords.whose(task(reason: .assigned, assignedBy: "Stijn"), me: "Stijn") == "Jij doet dit")
        #expect(TaskWords.whose(task(reason: .assigned), me: "Stijn") == "Jij doet dit")
        #expect(TaskWords.whose(task(reason: .addressee, forNames: ["Piet"]), me: "Stijn", locale: dutch)
            == "Voor jou en Piet")
        #expect(TaskWords.whose(task(reason: .addressee), me: "Stijn") == "Voor jou")
        #expect(TaskWords.whose(task(reason: .department, forNames: ["Finance"]), me: "Stijn") == "Voor Finance")
        #expect(TaskWords.whose(task(reason: .unassigned), me: "Stijn") == "Zonder naam")
        #expect(TaskWords.whose(task(reason: .unassigned, forNames: ["Piet", "Jan"]), me: "Stijn", locale: dutch)
            == "Voor Piet en Jan")
        #expect(TaskWords.whose(task(reason: .other, assignedTo: "Anne"), me: "Stijn") == "Bij Anne")
        #expect(TaskWords.whose(task(reason: .none), me: "Stijn") == nil)
    }

    @Test func fromForJoinsSenderAndWhose() {
        let both = task(sender: "Belastingdienst", reason: .addressee)
        #expect(TaskWords.fromFor(both, me: "Stijn") == "Van Belastingdienst · Voor jou")
        #expect(TaskWords.fromFor(task(sender: "CAK"), me: "Stijn") == "Van CAK")
        #expect(TaskWords.fromFor(task(), me: "Stijn") == nil)
    }

    @Test func whySaysWhereTheDateCameFrom() {
        let letter = task(deadline: "2026-12-01", deadlineSource: "in_document", quote: "vóór 1 december")
        #expect(TaskWords.why(letter) == "Uit de brief: ‘vóór 1 december’")
        #expect(TaskWords.why(task(deadline: "2026-12-01", deadlineSource: "manual")) == "Datum zelf ingevuld")
        #expect(TaskWords.why(task(deadlineSource: "manual")) == nil)
        #expect(TaskWords.why(task(deadline: "2026-12-01", deadlineSource: "in_document")) == nil)
    }

    @Test func needsDateQuotesTheTerm() {
        let term = task(needsDeadline: true, term: "binnen zes weken na dagtekening")
        #expect(TaskWords.needsDate(term)
            == "De brief noemt een termijn: ‘binnen zes weken na dagtekening’. Vul de datum in.")
        #expect(TaskWords.needsDate(task(needsDeadline: true)) == "Vul de datum in.")
        #expect(TaskWords.needsDate(task()) == nil)
    }

    @Test func theTypeWordIsLeftOutWhenTheDescriptionSaysIt() {
        #expect(TaskWords.typeWord(task(description: "Betaal de aanslag", type: "respond")) == "Reageren")
        #expect(TaskWords.typeWord(task(description: "Reageren op de brief", type: "respond")) == nil)
        #expect(TaskWords.typeWord(task(type: "")) == nil)
    }

    @Test func doneLineSaysWhoAndWhen() throws {
        let noon = CalendarDate(year: 2026, month: 11, day: 20).date(in: .current)
        #expect(TaskWords.doneLine(task(completedAt: noon, completedBy: "Anne"), locale: dutch)
            == "Afgevinkt door Anne op 20 nov")
        #expect(TaskWords.doneLine(task(completedAt: noon), locale: dutch) == "Afgevinkt op 20 nov")
        #expect(TaskWords.doneLine(task(), locale: dutch) == nil)
    }

    @Test func theTickBoxIsNamedAfterTheAction() {
        #expect(TaskWords.tickLabel(task(description: "Betaal de aanslag")) == "Klaar: Betaal de aanslag")
    }

    @Test func voiceOverReadsTheWholeRow() {
        let row = task(daysLeft: -1, deadline: "2026-11-20", amount: "12.5", sender: "CAK", reason: .addressee)
        #expect(TaskWords.accessibilityLabel(row, me: "Stijn", locale: dutch)
            == "Betaal de aanslag, 1 dag te laat (20 nov), €\u{00A0}12,50, Van CAK · Voor jou")
    }

    @Test func everyMyTasksKeyHasADutchValue() throws {
        for (key, resolved) in DocumentStrings.myTasksAll {
            #expect(try CatalogParity.dutchValue(forKey: key, target: "FeatureDocuments") == resolved, "\(key)")
        }
        let late = try CatalogParity.dutchPlural(forKey: "tasks.when.late", target: "FeatureDocuments")
        #expect(late == ["one": "%lld dag te laat (%@)", "other": "%lld dagen te laat (%@)"])
        let left = try CatalogParity.dutchPlural(forKey: "tasks.when.daysLeft", target: "FeatureDocuments")
        #expect(left["other"] == "Nog %lld dagen (%@)")
    }
}
