import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// The amount of a payment task in the review: pre-filled from the invoice in the user's notation, typed in the
/// user's notation, sent as the API's decimal string, and an unreadable amount blocks "Bevestigen".
@MainActor
@Suite struct ReviewAmountTests {
    private let harness = ReviewHarness()
    private static let dutch = Locale(identifier: "nl_NL")

    private func invoice() {
        harness.answer { id in
            DocumentFixtures.detail(id: id, proposals: [
                DocumentFixtures.proposal("invoice_due_date", "2026-12-01", quote: "vóór 1 december 2026"),
                DocumentFixtures.proposal("invoice_amount_incl", "1234.56", quote: "Totaal € 1.234,56")
            ])
        }
    }

    private func loaded() async throws -> ReviewModel {
        let model = try harness.model()
        model.locale = Self.dutch
        await model.load()
        return model
    }

    private func sentTasks() throws -> [TaskDraft] {
        let sent = harness.server.calls.compactMap { call -> ConfirmedReview? in
            if case let .confirm(_, _, review) = call { return review }
            return nil
        }
        return try #require(sent.first).tasks
    }

    @Test func payTaskIsPrefilledFromTheInvoiceAmount() async throws {
        invoice()

        let model = try await loaded()

        let pay = try #require(model.draft.tasks.first { $0.type == "pay" })
        #expect(pay.amount == "1.234,56")
        #expect(model.draft.quote(for: .taskAmount(pay.id)) == "Totaal € 1.234,56")
        #expect(model.amountIsValid(for: pay.id))
    }

    @Test func aTypedAmountGoesOutAsADecimalString() async throws {
        invoice()
        let model = try await loaded()
        let pay = try #require(model.draft.tasks.first { $0.type == "pay" })
        model.setAmount("€ 2.000,5", for: pay.id)
        harness.server.onConfirm { _, id, _ in DocumentFixtures.detail(id: id, status: .done) }

        await model.confirm()

        #expect(try sentTasks().first?.amount == "2000.50")
    }

    @Test func unreadableAmountBlocksConfirm() async throws {
        invoice()
        let model = try await loaded()
        let pay = try #require(model.draft.tasks.first { $0.type == "pay" })

        model.setAmount("twaalf", for: pay.id)
        await model.confirm()

        #expect(!model.amountIsValid(for: pay.id))
        #expect(model.saveError == "Dit bedrag kan Brievie niet lezen. Schrijf het als 1234,56.")
        #expect(!harness.server.calls.contains { if case .confirm = $0 { true } else { false } })
    }

    @Test func anEmptyAmountIsUnknownAndAllowed() async throws {
        invoice()
        let model = try await loaded()
        let pay = try #require(model.draft.tasks.first { $0.type == "pay" })
        model.setAmount("", for: pay.id)
        harness.server.onConfirm { _, id, _ in DocumentFixtures.detail(id: id, status: .done) }

        await model.confirm()

        #expect(try sentTasks().first?.amount == "")
    }

    @Test func amountFieldOnlyOnPayTasks() async throws {
        invoice()
        let model = try await loaded()
        model.addTask()
        let respond = try #require(model.draft.tasks.last)
        model.draft.tasks[model.draft.tasks.count - 1].description = "Bellen"
        model.setAmount("12,50", for: respond.id)
        harness.server.onConfirm { _, id, _ in DocumentFixtures.detail(id: id, status: .done) }

        await model.confirm()

        #expect(try sentTasks().last?.amount == "")
    }

    @Test func anInvoiceAmountTheLetterDoesNotSupportIsOnlyAHint() async throws {
        harness.answer { id in
            DocumentFixtures.detail(id: id, proposals: [
                DocumentFixtures.proposal("invoice_due_date", "2026-12-01", quote: "vóór 1 december 2026"),
                DocumentFixtures.proposal("invoice_amount_incl", "99.00", confidence: "0")
            ])
        }

        let model = try await loaded()

        let pay = try #require(model.draft.tasks.first { $0.type == "pay" })
        #expect(pay.amount.isEmpty)
        #expect(model.draft.unverified[.taskAmount(pay.id)] == "99,00")
    }
}
