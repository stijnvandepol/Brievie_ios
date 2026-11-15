import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// A review model against a fake server, shared by the suites below.
@MainActor
struct ReviewHarness {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")

    let documentID = UUID()
    let store = ConnectionStore(secrets: InMemorySecretStore())
    let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
    let events = EventLog()

    func model(canEdit: Bool = true) throws -> ReviewModel {
        let connection = ServerConnection(
            urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn"
        )
        try store.save(connection, token: "tok")
        return ReviewModel(
            documentID: documentID,
            documents: WorkspaceDocuments(
                workspaceID: UUID(), connection: connection, store: store, server: server
            ),
            canEdit: canEdit,
            onRevoked: { [events] in events.add("revoked") },
            onMissingPairing: { [events] in events.add("missing") }
        )
    }

    func answer(_ detail: @escaping @Sendable (UUID) -> DocumentDetail) {
        server.onDetail { _, id in detail(id) }
    }
}

/// From proposals to the draft the user sees.
@MainActor
@Suite struct ReviewDraftTests {
    private let harness = ReviewHarness()

    @Test func proposalsBecomeADraftWithOnePayTask() async throws {
        let model = try harness.model()

        await model.load()

        #expect(model.state == .review)
        #expect(model.draft.sender == "Belastingdienst")
        #expect(model.draft.senderQuote == "Belastingdienst")
        #expect(model.draft.documentType == "assessment")
        #expect(model.draft.letterDate == CalendarDate(year: 2026, month: 11, day: 3))
        #expect(model.draft.letterDateQuote == "Datum 3 november 2026")
        #expect(model.draft.summary == "Je moet belasting betalen.")
        #expect(model.draft.summaryIsByAI)
        let task = try #require(model.draft.tasks.first)
        #expect(model.draft.tasks.count == 1)
        #expect(task.type == "pay")
        #expect(task.description == "Betaal de aanslag")
        #expect(task.deadline == CalendarDate(year: 2026, month: 12, day: 1))
        #expect(task.deadlineSource == "in_document")
        #expect(task.deadlineQuote == "vóór 1 december 2026")
        #expect(!task.needsAttention)
        #expect(model.pageTexts == [DocumentFixtures.letterText])
    }

    @Test func draftFilledByAIIsMarkedAsSuch() async throws {
        // Final review, spec 14: every AI result is recognisable as AI, not only the summary.
        let filled = try harness.model()
        await filled.load()
        #expect(filled.draft.isFromAI)

        let empty = ReviewHarness()
        empty.answer { id in DocumentFixtures.detail(id: id, proposals: []) }
        let byHand = try empty.model()
        await byHand.load()
        #expect(!byHand.draft.isFromAI)
    }

    @Test func invoiceDueDateWithoutAPayActionAddsAPayTask() async throws {
        harness.answer { id in
            DocumentFixtures.detail(id: id, proposals: [
                DocumentFixtures.proposal("invoice_due_date", "2026-12-01", quote: "vóór 1 december 2026"),
                DocumentFixtures.proposal("action_type", "respond", group: 1),
                DocumentFixtures.proposal("action_description", "Bel de gemeente", group: 1)
            ])
        }
        let model = try harness.model()

        await model.load()

        #expect(model.draft.tasks.map(\.type) == ["respond", "pay"])
        let pay = try #require(model.draft.tasks.last)
        #expect(pay.description == DocumentStrings.payInvoice)
        #expect(pay.deadline == CalendarDate(year: 2026, month: 12, day: 1))
        #expect(pay.deadlineSource == "in_document")
        #expect(model.draft.tasks.first?.deadline == nil)
        #expect(model.draft.tasks.first?.deadlineSource == "manual")
    }

    @Test func invoiceDueDateDoesNotDuplicateAnExistingPayTask() async throws {
        harness.answer { id in
            DocumentFixtures.detail(id: id, proposals: [
                DocumentFixtures.proposal("invoice_due_date", "2026-12-01", quote: "vóór 1 december 2026"),
                DocumentFixtures.proposal("action_type", "pay", group: 1)
            ])
        }
        let model = try harness.model()

        await model.load()

        #expect(model.draft.tasks.count == 1)
    }

    @Test func valueTheLetterDoesNotSupportIsNotPrefilled() async throws {
        harness.answer { id in
            DocumentFixtures.detail(id: id, proposals: [
                DocumentFixtures.proposal("sender", "CAK", quote: "CAK", confidence: "0"),
                DocumentFixtures.proposal("action_type", "pay", group: 1),
                DocumentFixtures.proposal(
                    "action_deadline", "2026-12-15", quote: "vóór 15 december", group: 1, confidence: "0",
                    needsAttention: true
                )
            ])
        }
        let model = try harness.model()

        await model.load()

        #expect(model.draft.sender.isEmpty)
        #expect(model.draft.unverified["sender"] == "CAK")
        let task = try #require(model.draft.tasks.first)
        #expect(task.deadline == nil)
        #expect(task.deadlineSource == "manual")
        #expect(task.deadlineQuote.isEmpty)
        #expect(task.needsAttention)
    }

    @Test func lowConfidenceDeadlineIsPrefilledButFlagged() async throws {
        harness.answer { id in
            DocumentFixtures.detail(id: id, proposals: [
                DocumentFixtures.proposal("action_type", "pay", group: 1),
                DocumentFixtures.proposal(
                    "action_deadline", "2026-12-01", quote: "vóór 1 december 2026", group: 1, confidence: "0.6",
                    needsAttention: true
                )
            ])
        }
        let model = try harness.model()

        await model.load()

        #expect(model.draft.tasks.first?.deadline == CalendarDate(year: 2026, month: 12, day: 1))
        #expect(model.draft.tasks.first?.needsAttention == true)
    }

    @Test func editingADeadlineMakesItManual() async throws {
        // The source shown with a deadline must match the value (spec 14).
        let model = try harness.model()
        await model.load()
        let task = try #require(model.draft.tasks.first)

        model.setDeadline(CalendarDate(year: 2026, month: 12, day: 5), for: task.id)

        let edited = try #require(model.draft.tasks.first)
        #expect(edited.deadline == CalendarDate(year: 2026, month: 12, day: 5))
        #expect(edited.deadlineSource == "manual")
        #expect(edited.deadlineQuote.isEmpty)
        #expect(!edited.needsAttention)
    }

    @Test func settingTheSameDeadlineKeepsItsSource() async throws {
        let model = try harness.model()
        await model.load()
        let task = try #require(model.draft.tasks.first)

        model.setDeadline(task.deadline, for: task.id)

        #expect(model.draft.tasks.first?.deadlineSource == "in_document")
    }
}

/// Confirming, retrying and what the server answers.
@MainActor
@Suite struct ReviewModelTests {
    private let harness = ReviewHarness()

    @Test func confirmSendsExactlyTheEditedDraft() async throws {
        let model = try harness.model()
        await model.load()
        model.draft.sender = "Belastingdienst Toeslagen"
        model.draft.summary = "Zelf geschreven uitleg"
        model.addTask()
        let added = try #require(model.draft.tasks.last)
        model.draft.tasks[1].description = "Bellen"
        model.draft.tasks[1].type = "respond"
        let confirmedID = harness.documentID
        harness.server.onConfirm { _, id, _ in
            DocumentFixtures.detail(id: id, status: .done, tasks: [ConfirmedTask(
                id: UUID(), type: "pay", description: "Betaal de aanslag",
                deadline: CalendarDate(year: 2026, month: 12, day: 1), deadlineSource: "in_document",
                deadlineQuote: "vóór 1 december 2026"
            )])
        }

        await model.confirm()

        #expect(model.state == .done)
        #expect(model.detail?.tasks.count == 1)
        let sent = try #require(harness.server.calls.compactMap { call -> ConfirmedReview? in
            if case let .confirm(_, id, review) = call, id == confirmedID { return review }
            return nil
        }.first)
        #expect(sent.sender == "Belastingdienst Toeslagen")
        #expect(sent.documentType == "assessment")
        #expect(sent.letterDate == CalendarDate(year: 2026, month: 11, day: 3))
        #expect(sent.summary == "Zelf geschreven uitleg")
        #expect(!sent.summaryByAI)
        #expect(sent.tasks.map(\.type) == ["pay", "respond"])
        #expect(sent.tasks[0].deadlineQuote == "vóór 1 december 2026")
        #expect(sent.tasks[1].id == added.id)
        #expect(sent.tasks[1].deadlineSource == "manual")
    }

    @Test func untouchedAISummaryIsSentAsAIText() async throws {
        let model = try harness.model()
        await model.load()
        harness.server.onConfirm { _, id, _ in DocumentFixtures.detail(id: id, status: .done) }

        await model.confirm()

        let sent = harness.server.calls.compactMap { call -> ConfirmedReview? in
            if case let .confirm(_, _, review) = call { return review }
            return nil
        }
        #expect(sent.first?.summaryByAI == true)
    }

    @Test func taskWithoutDescriptionBlocksConfirmWithAMessage() async throws {
        let model = try harness.model()
        await model.load()
        model.addTask()

        await model.confirm()

        #expect(model.state == .review)
        #expect(model.saveError == DocumentStrings.taskNeedsDescription)
        #expect(!harness.server.calls.contains { if case .confirm = $0 { true } else { false } })
    }

    @Test func tasksCanBeRemoved() async throws {
        let model = try harness.model()
        await model.load()
        let task = try #require(model.draft.tasks.first)

        model.removeTask(task.id)

        #expect(model.draft.tasks.isEmpty)
    }

    @Test func processingDocumentWaitsAndThenOffersTheReview() async throws {
        harness.answer { id in DocumentFixtures.detail(id: id, status: .processing, proposals: []) }
        let model = try harness.model()
        await model.load()
        #expect(model.state == .processing)

        harness.answer { id in DocumentFixtures.detail(id: id) }
        await model.refreshIfProcessing()

        #expect(model.state == .review)
        #expect(model.draft.sender == "Belastingdienst")
        let calls = harness.server.calls.count
        await model.refreshIfProcessing()
        #expect(harness.server.calls.count == calls)
    }

    @Test func aiOffGivesAnEmptyDraftThatCanBeConfirmedByHand() async throws {
        // Review Focus 5
        harness.answer { id in DocumentFixtures.detail(id: id, proposals: []) }
        let model = try harness.model()
        await model.load()
        #expect(model.state == .review)
        #expect(model.draft == ReviewModel.Draft())

        model.addTask()
        model.draft.tasks[0].description = "Betalen"
        model.setDeadline(CalendarDate(year: 2026, month: 12, day: 1), for: model.draft.tasks[0].id)
        harness.server.onConfirm { _, id, _ in DocumentFixtures.detail(id: id, status: .done) }
        await model.confirm()

        #expect(model.state == .done)
    }

    @Test func failedDocumentCanBeFilledInOrProcessedAgain() async throws {
        harness.answer { id in
            DocumentFixtures.detail(id: id, status: .failed, proposals: [], failureCode: "ai_unavailable")
        }
        let model = try harness.model()
        await model.load()
        #expect(model.state == .review)
        #expect(model.processingFailed)

        harness.server.onRetry { _, id in DocumentFixtures.detail(id: id, status: .processing, proposals: []) }
        await model.retryProcessing()

        #expect(model.state == .processing)
        #expect(!model.processingFailed)
    }

    @Test func confirmedDocumentShowsItsTasks() async throws {
        let task = ConfirmedTask(
            id: UUID(), type: "pay", description: "Betalen", deadline: CalendarDate(year: 2026, month: 12, day: 1),
            deadlineSource: "in_document", deadlineQuote: "vóór 1 december 2026"
        )
        harness.answer { id in DocumentFixtures.detail(id: id, status: .done, tasks: [task]) }
        let model = try harness.model()

        await model.load()

        #expect(model.state == .done)
        #expect(model.detail?.tasks == [task])
    }

    @Test func conflictOnConfirmReloadsTheDocument() async throws {
        let model = try harness.model()
        await model.load()
        harness.server.onConfirm { _, _, _ in throw ServerError.other("document_not_reviewable") }
        harness.answer { id in DocumentFixtures.detail(id: id, status: .done) }

        await model.confirm()

        #expect(model.state == .done)
    }

    @Test func refusedReviewKeepsTheDraftAndExplains() async throws {
        let model = try harness.model()
        await model.load()
        model.draft.sender = "Aangepast"
        harness.server.onConfirm { _, _, _ in throw ServerError.other("validation_error") }

        await model.confirm()

        #expect(model.state == .review)
        #expect(model.draft.sender == "Aangepast")
        #expect(model.saveError == DocumentStrings.reviewRefused)
    }

    @Test func revokedDeviceEndsTheSession() async throws {
        harness.server.onDetail { _, _ in throw ServerError.unauthorized }
        let model = try harness.model()

        await model.load()

        #expect(harness.events.all == ["revoked"])
    }

    @Test func unreachableServerShowsAMessage() async throws {
        harness.server.onDetail { _, _ in throw ServerError.unreachable }
        let model = try harness.model()

        await model.load()

        #expect(model.state == .failed(message: DocumentStrings.unreachable))
    }

    @Test func viewerMayNotEdit() async throws {
        let model = try harness.model(canEdit: false)
        await model.load()

        await model.confirm()

        #expect(!model.canEdit)
        #expect(!harness.server.calls.contains { if case .confirm = $0 { true } else { false } })
    }

    @Test func pageImagesAreLoadedOncePerPage() async throws {
        let model = try harness.model()
        await model.load()

        await model.loadPage(1)
        await model.loadPage(1)

        #expect(model.pages[1] == Data([0xFF, 0xD8, 0xFF]))
        #expect(harness.server.calls.filter { if case .page = $0 { true } else { false } }.count == 1)
    }

    @Test func unknownTypesFallBackToOther() async throws {
        harness.answer { id in
            DocumentFixtures.detail(id: id, proposals: [
                DocumentFixtures.proposal("document_type", "hologram"),
                DocumentFixtures.proposal("action_type", "teleport", group: 1)
            ])
        }
        let model = try harness.model()

        await model.load()

        #expect(model.draft.documentType == "other")
        #expect(model.draft.tasks.first?.type == "other")
    }
}
