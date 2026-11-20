import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// The host dismisses every proposal not taken when a letter is confirmed with the lists
/// (`review._set_organisation`), and nothing automatic proposes it there again. The review says so before
/// "Bevestigen", naming what is still open (simulator, 20-11-2026: "Wonen" vanished without notice).
@MainActor
@Suite struct ReviewOpenProposalsTests {
    private let harness = ReviewHarness()

    init() {
        harness.answer { id in DocumentFixtures.detailWithSuggestions(id: id) }
    }

    @Test func anOpenProposalIsNamedBeforeConfirming() async throws {
        let model = try harness.model()
        await model.load()

        // "Stijn" starts ticked (preselected); the label "Belasting" is still open.
        #expect(model.openProposalsNote == String(format: DocumentStrings.openProposalsOneFormat, "Belasting"))
    }

    @Test func takingTheProposalRemovesTheNote() async throws {
        let model = try harness.model()
        await model.load()
        let label = try #require(model.draft.organise.openSuggestions(for: .addLabel).first)

        model.draft.organise.toggle(label)

        #expect(model.openProposalsNote == nil)
    }

    @Test func untickingAPreselectedProposalCountsItToo() async throws {
        let model = try harness.model()
        await model.load()
        let person = try #require(model.draft.organise.suggestions.first { $0.action == .addAddressee })

        model.draft.organise.toggle(person)

        let expected = String(format: DocumentStrings.openProposalsManyFormat, 2, "Stijn, Belasting")
        #expect(model.openProposalsNote == expected)
    }

    @Test func withoutTheListsNothingIsDismissedAndNothingIsSaid() async throws {
        harness.server.onPersons { _ in throw ServerError.other("not_found") }
        harness.server.onLabels { _ in throw ServerError.other("not_found") }
        let model = try harness.model()
        await model.load()

        #expect(model.openProposalsNote == nil)
    }

    @Test func theWordingIsInTheCatalog() throws {
        for (key, value) in [
            ("review.proposals.open.one", DocumentStrings.openProposalsOneFormat),
            ("review.proposals.open.many", DocumentStrings.openProposalsManyFormat)
        ] {
            #expect(try CatalogParity.dutchValue(forKey: key, target: "FeatureDocuments") == value)
        }
    }
}
