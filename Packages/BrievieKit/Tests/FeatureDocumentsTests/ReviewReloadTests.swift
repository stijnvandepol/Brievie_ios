import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// The screen of one letter: its title, and fresh persons and labels when a confirmed letter loads again.
@MainActor
@Suite struct ReviewReloadTests {
    private let harness = ReviewHarness()

    @Test func aLetterInReviewIsTitledControleren() async throws {
        let model = try harness.model()
        #expect(model.title == DocumentStrings.reviewTitle)

        await model.load()

        #expect(model.state == .review)
        #expect(model.title == "Controleren")
    }

    @Test func aConfirmedLetterIsTitledBrief() async throws {
        harness.answer { DocumentFixtures.detail(id: $0, status: .done) }
        let model = try harness.model()

        await model.load()

        #expect(model.state == .done)
        #expect(model.title == DocumentStrings.letterTitle)
        #expect(model.title == "Brief")
    }

    @Test func loadingAConfirmedLetterAgainFetchesThePersonsAndLabelsAgain() async throws {
        harness.answer { DocumentFixtures.detail(id: $0, status: .done) }
        let model = try harness.model()
        await model.load()
        #expect(model.confirmed?.labels == DocumentFixtures.labels)
        // Made in the web while the screen was away.
        let post = DocumentLabel(id: UUID(), name: "Post", colorKey: "blue")
        let opa = Person(id: UUID(), displayName: "Opa", nameVariants: [], isArchived: false)
        harness.server.onLabels { _ in DocumentFixtures.labels + [post] }
        harness.server.onPersons { _ in DocumentFixtures.persons + [opa] }

        await model.load()

        #expect(model.labels == DocumentFixtures.labels + [post])
        #expect(model.confirmed?.labels == DocumentFixtures.labels + [post])
        #expect(model.confirmed?.persons == DocumentFixtures.persons + [opa])
    }

    @Test func listsThatCannotBeLoadedAgainKeepTheOldOnes() async throws {
        harness.answer { DocumentFixtures.detail(id: $0, status: .done) }
        let model = try harness.model()
        await model.load()
        harness.server.onLabels { _ in throw ServerError.unreachable }

        await model.load()

        #expect(model.organiseAvailable)
        #expect(model.confirmed?.labels == DocumentFixtures.labels)
    }

    @Test func aLetterInReviewDoesNotAskForTheListsOnEveryLoad() async throws {
        let model = try harness.model()
        await model.load()
        let before = labelCalls()

        await model.load()

        #expect(labelCalls() == before)
    }

    private func labelCalls() -> Int {
        harness.server.calls.count { call in
            if case .labels = call { return true }
            return false
        }
    }
}
