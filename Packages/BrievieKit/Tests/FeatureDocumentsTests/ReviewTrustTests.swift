import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// Every value the user confirms shows where it comes from and how sure the AI is (plan 1b, Global Constraints).
@MainActor
@Suite struct ReviewTrustTests {
    private let harness = ReviewHarness()

    private func load(_ proposals: [Proposal]) async throws -> ReviewModel {
        harness.answer { id in DocumentFixtures.detail(id: id, proposals: proposals) }
        let model = try harness.model()
        await model.load()
        return model
    }

    @Test func everyFieldBelowTheThresholdIsMarked() async throws {
        let model = try await load([
            DocumentFixtures.proposal("sender", "CAK", quote: "CAK", confidence: "0.6"),
            DocumentFixtures.proposal("document_type", "invoice", quote: "Factuur", confidence: "0.84"),
            DocumentFixtures.proposal("letter_date", "2026-11-03", quote: "3 november", confidence: "0.5"),
            DocumentFixtures.proposal("action_type", "pay", quote: "betalen", group: 1, confidence: "0.7"),
            DocumentFixtures.proposal(
                "action_description", "Betaal de rekening", quote: "betalen", group: 1, confidence: "0.7"
            )
        ])
        let task = try #require(model.draft.tasks.first)

        let fields: [ReviewField] = [
            .sender, .documentType, .letterDate, .taskType(task.id), .taskDescription(task.id)
        ]
        for field in fields {
            #expect(model.draft.needsAttention(field), "\(field)")
            #expect(!model.draft.quote(for: field).isEmpty, "\(field)")
        }
    }

    @Test func valueWithoutAQuoteIsMarked() async throws {
        let model = try await load([
            DocumentFixtures.proposal("sender", "CAK", confidence: "0.99"),
            DocumentFixtures.proposal("document_type", "invoice", confidence: "0.99")
        ])

        #expect(model.draft.sender == "CAK")
        #expect(model.draft.needsAttention(.sender))
        #expect(model.draft.needsAttention(.documentType))
        #expect(model.draft.quote(for: .sender).isEmpty)
    }

    @Test func valueTheServerFlagsIsMarkedWhateverItsConfidence() async throws {
        let model = try await load([
            DocumentFixtures.proposal("sender", "CAK", quote: "CAK", confidence: "0.99", needsAttention: true)
        ])

        #expect(model.draft.needsAttention(.sender))
    }

    @Test func sureValueWithAQuoteIsNotMarked() async throws {
        let model = try await load([
            DocumentFixtures.proposal("sender", "CAK", quote: "CAK", confidence: "0.85")
        ])

        #expect(!model.draft.needsAttention(.sender))
        #expect(model.draft.quote(for: .sender) == "CAK")
    }

    @Test func valuesAtConfidenceZeroAreHintsNotPrefilled() async throws {
        let model = try await load([
            DocumentFixtures.proposal("document_type", "invoice", quote: "Factuur", confidence: "0"),
            DocumentFixtures.proposal("action_type", "pay", quote: "betalen", group: 1, confidence: "0"),
            DocumentFixtures.proposal(
                "action_description", "Betaal de rekening", quote: "betalen", group: 1, confidence: "0"
            ),
            DocumentFixtures.proposal(
                "action_deadline", "2026-12-15", quote: "vóór 15 december", group: 1, confidence: "0"
            )
        ])
        let task = try #require(model.draft.tasks.first)

        #expect(model.draft.documentType.isEmpty)
        #expect(model.draft.unverified[.documentType] == DocumentStrings.docTypeInvoice)
        #expect(task.type == "other")
        #expect(model.draft.unverified[.taskType(task.id)] == DocumentStrings.taskTypePay)
        #expect(task.description.isEmpty)
        #expect(model.draft.unverified[.taskDescription(task.id)] == "Betaal de rekening")
        #expect(task.deadline == nil)
        #expect(model.draft.unverified[.taskDeadline(task.id)] == CalendarDate(year: 2026, month: 12, day: 15).display)
        #expect(model.draft.quote(for: .taskDeadline(task.id)).isEmpty)
    }

    @Test func payTaskTheAppAddsIsMarkedAsUnchecked() async throws {
        let model = try await load([
            DocumentFixtures.proposal("invoice_due_date", "2026-12-01", quote: "vóór 1 december 2026")
        ])
        let pay = try #require(model.draft.tasks.first)

        #expect(model.draft.isUnchecked(.taskType(pay.id)))
        #expect(model.draft.isUnchecked(.taskDescription(pay.id)))
        #expect(!model.draft.isUnchecked(.taskDeadline(pay.id)))
        #expect(model.draft.quote(for: .taskDeadline(pay.id)) == "vóór 1 december 2026")
    }

    @Test func editedValueLosesItsQuoteAndMarkUntilRestored() async throws {
        let model = try await load([
            DocumentFixtures.proposal("sender", "CAK", quote: "CAK", confidence: "0.6"),
            DocumentFixtures.proposal("letter_date", "2026-11-03", quote: "3 november", confidence: "0.6"),
            DocumentFixtures.proposal("action_type", "pay", quote: "betalen", group: 1, confidence: "0.6")
        ])
        let task = try #require(model.draft.tasks.first)

        model.draft.sender = "CAK Den Haag"
        model.draft.letterDate = CalendarDate(year: 2026, month: 11, day: 4)
        model.draft.tasks[0].type = "respond"

        #expect(model.draft.quote(for: .sender).isEmpty)
        #expect(!model.draft.needsAttention(.sender))
        #expect(model.draft.senderQuote.isEmpty)
        #expect(model.draft.letterDateQuote.isEmpty)
        #expect(!model.draft.needsAttention(.letterDate))
        #expect(model.draft.quote(for: .taskType(task.id)).isEmpty)

        model.draft.sender = "CAK"
        model.draft.letterDate = CalendarDate(year: 2026, month: 11, day: 3)
        model.draft.tasks[0].type = "pay"

        #expect(model.draft.quote(for: .sender) == "CAK")
        #expect(model.draft.needsAttention(.sender))
        #expect(model.draft.letterDateQuote == "3 november")
        #expect(model.draft.needsAttention(.taskType(task.id)))
    }

    @Test func restoringTheOriginalDeadlineRestoresItsSource() async throws {
        let model = try harness.model()
        await model.load()
        let task = try #require(model.draft.tasks.first)
        let original = task.deadline

        model.setDeadline(CalendarDate(year: 2026, month: 12, day: 5), for: task.id)
        #expect(model.draft.quote(for: .taskDeadline(task.id)).isEmpty)
        model.setDeadline(original, for: task.id)

        let restored = try #require(model.draft.tasks.first)
        #expect(restored.deadlineSource == "in_document")
        #expect(restored.deadlineQuote == "vóór 1 december 2026")
        #expect(model.draft.quote(for: .taskDeadline(task.id)) == "vóór 1 december 2026")
    }
}

/// The user's own edits survive what the server answers.
@MainActor
@Suite struct ReviewEditsTests {
    private let harness = ReviewHarness()

    @Test func conflictWhileStillWaitingForReviewKeepsTheDraftAndExplains() async throws {
        let model = try harness.model()
        await model.load()
        model.draft.sender = "Aangepast"
        harness.server.onConfirm { _, _, _ in throw ServerError.other("document_not_reviewable") }

        await model.confirm()

        #expect(model.state == .review)
        #expect(model.draft.sender == "Aangepast")
        #expect(model.saveError == DocumentStrings.confirmConflict)
    }

    @Test func retryProcessingAsksFirstWhenTheDraftWasEdited() async throws {
        harness.answer { id in
            DocumentFixtures.detail(id: id, status: .failed, proposals: [], failureCode: "ai_unavailable")
        }
        let model = try harness.model()
        await model.load()
        model.draft.sender = "Zelf getypt"
        harness.server.onRetry { _, id in DocumentFixtures.detail(id: id, status: .processing, proposals: []) }

        await model.retryProcessing()

        #expect(model.confirmsDiscardingEdits)
        #expect(model.draft.sender == "Zelf getypt")
        #expect(!harness.server.calls.contains { if case .retry = $0 { true } else { false } })

        await model.retryProcessing(discardingEdits: true)

        #expect(!model.confirmsDiscardingEdits)
        #expect(model.state == .processing)
    }

    @Test func retryProcessingOfAnUntouchedDraftDoesNotAsk() async throws {
        harness.answer { id in
            DocumentFixtures.detail(id: id, status: .failed, proposals: [], failureCode: "ai_unavailable")
        }
        let model = try harness.model()
        await model.load()
        harness.server.onRetry { _, id in DocumentFixtures.detail(id: id, status: .processing, proposals: []) }

        await model.retryProcessing()

        #expect(!model.confirmsDiscardingEdits)
        #expect(model.state == .processing)
    }
}
