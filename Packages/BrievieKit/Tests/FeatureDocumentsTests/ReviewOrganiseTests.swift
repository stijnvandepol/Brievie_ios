import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// The review's "Op naam van" and "Labels": loading the lists, confirming the choice, a new person.
@MainActor
@Suite struct ReviewOrganiseTests {
    private let harness = ReviewHarness()
    private let stijn = DocumentFixtures.persons[0].id
    private let zorg = DocumentFixtures.labels[0].id
    private let belasting = DocumentFixtures.labels[1].id

    init() {
        harness.answer { id in DocumentFixtures.detailWithSuggestions(id: id) }
        harness.server.onConfirm { _, id, _ in DocumentFixtures.detail(id: id, status: .done) }
    }

    @Test func confirmSendsTheChosenSets() async throws {
        let model = try harness.model()
        await model.load()
        #expect(model.organiseAvailable)
        #expect(model.persons == DocumentFixtures.persons)
        #expect(model.labels == DocumentFixtures.labels)
        let label = try #require(model.draft.organise.openSuggestions(for: .addLabel).first)
        model.draft.organise.toggle(label)

        await model.confirm()

        let sent = try #require(sentReviews().first)
        #expect(sent.setsOrganisation)
        #expect(Set(sent.addresseeIDs) == [stijn])
        #expect(Set(sent.labelIDs) == [belasting])
        #expect(model.state == .done)
    }

    @Test func confirmAgainstA1bServerSendsNoOrganisation() async throws {
        harness.server.onPersons { _ in throw ServerError.other("not_found") }
        harness.server.onLabels { _ in throw ServerError.other("not_found") }
        let model = try harness.model()
        await model.load()
        #expect(model.state == .review)
        #expect(!model.organiseAvailable)
        #expect(model.persons.isEmpty)
        #expect(model.labels.isEmpty)

        await model.confirm()

        let sent = try #require(sentReviews().first)
        #expect(!sent.setsOrganisation)
        #expect(sent.addresseeIDs.isEmpty)
        #expect(sent.labelIDs.isEmpty)
    }

    @Test func newPersonIsCreatedAndSelected() async throws {
        let papa = Person(id: UUID(), displayName: "Papa", nameVariants: [], isArchived: false)
        harness.server.onCreatePerson { _, _ in papa }
        let model = try harness.model()
        await model.load()

        let created = await model.createPerson(named: "  Papa ")

        #expect(created)
        #expect(model.persons.contains(papa))
        #expect(model.draft.organise.addresseeIDs == [stijn, papa.id])
        #expect(model.personError == nil)
        #expect(harness.server.calls.contains { if case .createPerson(_, "Papa") = $0 { true } else { false } })
    }

    @Test func duplicatePersonNameShowsTheMessage() async throws {
        harness.server.onCreatePerson { _, _ in throw ServerError.other("person_exists") }
        let model = try harness.model()
        await model.load()

        let created = await model.createPerson(named: "Stijn")

        #expect(!created)
        #expect(model.personError == DocumentStrings.nameTaken)
        #expect(model.persons == DocumentFixtures.persons)
        #expect(model.draft.organise.addresseeIDs == [stijn])
    }

    @Test func deletedLabelOnConfirmKeepsTheDraftAndExplains() async throws {
        let model = try harness.model()
        await model.load()
        model.draft.sender = "Zelf aangepast"
        model.draft.organise.setLabels([zorg, belasting])
        // "Zorg" is deleted in the web while the review is open.
        harness.server.onConfirm { _, _, _ in throw ServerError.other("label_not_found") }
        harness.server.onLabels { _ in [DocumentFixtures.labels[1]] }

        await model.confirm()

        #expect(model.state == .review)
        #expect(model.saveError == DocumentStrings.organiseGone)
        #expect(model.labels == [DocumentFixtures.labels[1]])
        #expect(model.draft.organise.labelIDs == [belasting])
        #expect(model.draft.organise.addresseeIDs == [stijn])
        #expect(model.draft.sender == "Zelf aangepast")
    }

    @Test func removingAPreselectedPersonLeavesThemOutOfTheConfirm() async throws {
        let model = try harness.model()
        await model.load()
        model.draft.organise.setAddressees([])

        await model.confirm()

        let sent = try #require(sentReviews().first)
        #expect(sent.setsOrganisation)
        #expect(sent.addresseeIDs.isEmpty)
        #expect(sent.labelIDs.isEmpty)
    }

    private func sentReviews() -> [ConfirmedReview] {
        harness.server.calls.compactMap { call in
            if case let .confirm(_, _, review) = call { return review }
            return nil
        }
    }
}
