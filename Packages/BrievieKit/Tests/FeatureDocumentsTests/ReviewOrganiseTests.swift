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

    @Test func oneListFailingHidesTheSectionsAndConfirmsWithoutThem() async throws {
        harness.server.onLabels { _ in throw ServerError.unreachable }
        let model = try harness.model()
        await model.load()
        #expect(model.state == .review)
        #expect(!model.organiseAvailable)

        await model.confirm()

        let sent = try #require(sentReviews().first)
        #expect(!sent.setsOrganisation)
        #expect(sent.addresseeIDs.isEmpty)
        #expect(sent.labelIDs.isEmpty)
    }

    @Test func duplicatePersonNameReloadsThePersons() async throws {
        let papa = Person(id: UUID(), displayName: "Papa", nameVariants: [], isArchived: false)
        harness.server.onCreatePerson { _, _ in throw ServerError.other("person_exists") }
        let model = try harness.model()
        await model.load()
        // Papa was made in the web while the review was open.
        harness.server.onPersons { _ in DocumentFixtures.persons + [papa] }

        await model.createPerson(named: "Papa")

        #expect(model.personError == DocumentStrings.nameTaken)
        #expect(model.persons.contains(papa))
        #expect(model.draft.organise.addresseeIDs == [stijn])
    }

    @Test func leavingTheForegroundClosesThePickerAndTheLetterText() async throws {
        let model = try harness.model()
        await model.load()
        model.pick(.persons)
        #expect(model.picker == .persons)

        model.sceneDidChange(isActive: false)

        #expect(model.picker == nil, "Names and a half-typed new person must not show above the lock screen")
        model.showQuote("Stijn de Vries")
        #expect(model.shownQuote?.text == "Stijn de Vries")

        model.sceneDidChange(isActive: false)

        #expect(model.shownQuote == nil)
        #expect(model.draft.organise.addresseeIDs == [stijn], "Closing the sheets keeps the draft")
    }

    @Test func leavingTheForegroundClosesTheLabelPickerOfAConfirmedLetter() async throws {
        harness.answer { id in DocumentFixtures.detail(id: id, status: .done) }
        let model = try harness.model()
        await model.load()
        #expect(model.confirmed != nil)
        model.pick(.labels)

        model.sceneDidChange(isActive: false)

        #expect(model.picker == nil)
    }

    @Test func openingThePersonPickerClearsAnOldError() async throws {
        harness.server.onCreatePerson { _, _ in throw ServerError.other("person_exists") }
        let model = try harness.model()
        await model.load()
        await model.createPerson(named: "Stijn")
        #expect(model.personError != nil)

        model.pick(.persons)

        #expect(model.personError == nil)
    }

    @Test func notFoundWhileTheReloadFailsKeepsTheDraft() async throws {
        let model = try harness.model()
        await model.load()
        model.draft.sender = "Zelf aangepast"
        model.draft.organise.setLabels([zorg, belasting])
        harness.server.onConfirm { _, _, _ in throw ServerError.other("label_not_found") }
        harness.server.onDetail { _, _ in throw ServerError.unreachable }

        await model.confirm()

        #expect(model.state == .review)
        #expect(model.draft.sender == "Zelf aangepast")
        #expect(model.draft.organise.labelIDs == [zorg, belasting])
        #expect(model.saveError == DocumentStrings.unreachable)
    }

    @Test func notFoundForTheDocumentItselfShowsItIsGone() async throws {
        let model = try harness.model()
        await model.load()
        harness.server.onConfirm { _, _, _ in throw ServerError.other("document_not_found") }
        harness.server.onDetail { _, _ in throw ServerError.other("document_not_found") }

        await model.confirm()

        #expect(model.state == .failed(message: DocumentStrings.notFound))
    }

    @Test func notFoundWhileTheListsFailKeepsTheChoiceAndSaysItDidNotWork() async throws {
        let model = try harness.model()
        await model.load()
        model.draft.organise.setLabels([zorg, belasting])
        harness.server.onConfirm { _, _, _ in throw ServerError.other("label_not_found") }
        harness.server.onLabels { _ in throw ServerError.unreachable }

        await model.confirm()

        #expect(model.state == .review)
        #expect(model.organiseAvailable)
        #expect(model.labels == DocumentFixtures.labels)
        #expect(model.draft.organise.labelIDs == [zorg, belasting])
        #expect(model.saveError == DocumentStrings.generic)
    }

    private func sentReviews() -> [ConfirmedReview] {
        harness.server.calls.compactMap { call in
            if case let .confirm(_, _, review) = call { return review }
            return nil
        }
    }
}
