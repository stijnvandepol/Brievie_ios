import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// On whose name and which labels: what the review starts with and how the user changes it.
@Suite struct OrganiseDraftTests {
    private let stijn = DocumentFixtures.persons[0].id
    private let belasting = DocumentFixtures.labels[1].id
    private let zorg = DocumentFixtures.labels[0].id

    @Test func preselectedSuggestionStartsChosen() {
        let draft = OrganiseDraft(detail: DocumentFixtures.detailWithSuggestions())

        #expect(draft.addresseeIDs == [stijn])
        #expect(draft.openSuggestions(for: .addAddressee).isEmpty)
    }

    @Test func aiSuggestionStartsOpen() {
        let draft = OrganiseDraft(detail: DocumentFixtures.detailWithSuggestions())

        #expect(draft.labelIDs.isEmpty)
        #expect(draft.openSuggestions(for: .addLabel).map(\.targetID) == [belasting])
        #expect(draft.openSuggestions(for: .addLabel).first?.origin == .ai)
    }

    @Test func alreadyAppliedLabelStartsChosen() {
        // An automatic rule put "Zorg" and Anne on the letter before the review: no suggestion, just there.
        let anne = DocumentFixtures.persons[1].id
        let draft = OrganiseDraft(detail: Self.detail(addresseeIDs: [anne], labelIDs: [zorg]))

        #expect(draft.labelIDs == [zorg])
        #expect(draft.addresseeIDs == [anne, stijn])
        #expect(draft.origin(ofLabel: zorg) == nil)
    }

    @Test func toggleMovesASuggestionBetweenOpenAndChosen() throws {
        var draft = OrganiseDraft(detail: DocumentFixtures.detailWithSuggestions())
        let label = try #require(draft.openSuggestions(for: .addLabel).first)

        draft.toggle(label)

        #expect(draft.labelIDs == [belasting])
        #expect(draft.openSuggestions(for: .addLabel).isEmpty)

        draft.toggle(label)

        #expect(draft.labelIDs.isEmpty)
        #expect(draft.openSuggestions(for: .addLabel) == [label])
    }

    @Test func chosenTargetKeepsItsOrigin() throws {
        var draft = OrganiseDraft(detail: DocumentFixtures.detailWithSuggestions())
        let label = try #require(draft.openSuggestions(for: .addLabel).first)

        #expect(draft.origin(ofAddressee: stijn)?.origin == .nameMatch)
        #expect(draft.origin(ofAddressee: stijn)?.quote == "S. van de Pol")
        #expect(draft.origin(ofLabel: belasting) == nil)

        draft.setLabels([belasting, zorg])

        #expect(draft.origin(ofLabel: belasting) == label)
        #expect(draft.origin(ofLabel: zorg) == nil)

        draft.setAddressees([])

        #expect(draft.origin(ofAddressee: stijn) == nil)
        #expect(draft.openSuggestions(for: .addAddressee).map(\.targetID) == [stijn])
    }

    /// The letter with suggestions, after an automatic rule put `addresseeIDs` and `labelIDs` on it.
    static func detail(addresseeIDs: [UUID], labelIDs: [UUID]) -> DocumentDetail {
        let base = DocumentFixtures.detailWithSuggestions()
        let summary = base.summary
        return DocumentDetail(
            summary: DocumentSummary(
                id: summary.id, clientID: summary.clientID, status: summary.status, pageCount: summary.pageCount,
                createdAt: summary.createdAt, sender: summary.sender, documentType: summary.documentType,
                letterDate: summary.letterDate, inboxState: summary.inboxState, addresseeIDs: addresseeIDs,
                labelIDs: labelIDs, openSuggestionCount: summary.openSuggestionCount
            ),
            failureCode: base.failureCode, summaryText: base.summaryText, summaryByAI: base.summaryByAI,
            pageTexts: base.pageTexts, proposals: base.proposals, tasks: base.tasks, suggestions: base.suggestions
        )
    }
}
