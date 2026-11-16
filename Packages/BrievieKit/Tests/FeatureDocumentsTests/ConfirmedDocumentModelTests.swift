import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// A confirmed letter: its addressees and labels change at once, open suggestions are taken or dropped, tasks
/// are ticked off.
@MainActor
@Suite struct ConfirmedDocumentModelTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")

    private let documentID = UUID()
    private let taskID = UUID()
    private let store = ConnectionStore(secrets: InMemorySecretStore())
    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id, status: .done) }
    private let events = EventLog()
    private let stijn = DocumentFixtures.persons[0].id
    private let anne = DocumentFixtures.persons[1].id
    private let zorg = DocumentFixtures.labels[0].id
    private let belasting = DocumentFixtures.labels[1].id

    /// The confirmed letter on Stijn's name with the label "Zorg", one open task and two open suggestions:
    /// Anne as addressee and the label "Belasting".
    private func detail(
        addressees: [UUID]? = nil, labels: [UUID]? = nil, suggestions: [Suggestion]? = nil
    ) -> DocumentDetail {
        let base = DocumentFixtures.detail(id: documentID, status: .done)
        let summary = base.summary
        return DocumentDetail(
            summary: DocumentSummary(
                id: summary.id, clientID: summary.clientID, status: .done, pageCount: summary.pageCount,
                createdAt: summary.createdAt, sender: "Belastingdienst", documentType: "assessment",
                letterDate: nil, addresseeIDs: addressees ?? [stijn], labelIDs: labels ?? [zorg]
            ),
            failureCode: "", summaryText: "", summaryByAI: false, pageTexts: base.pageTexts, proposals: [],
            tasks: [ConfirmedTask(
                id: taskID, type: "pay", description: "Betaal de aanslag", deadline: nil, deadlineSource: "manual",
                deadlineQuote: ""
            )],
            suggestions: suggestions ?? [anneSuggestion, belastingSuggestion]
        )
    }

    private var anneSuggestion: Suggestion {
        Suggestion(
            id: UUID(uuidString: "11111111-2222-4333-8444-555555555555") ?? UUID(), action: .addAddressee,
            targetID: anne, origin: .nameMatch, ruleName: "", quote: "", confidence: 1, isPreselected: false
        )
    }

    private var belastingSuggestion: Suggestion {
        Suggestion(
            id: UUID(uuidString: "66666666-7777-4888-9999-AAAAAAAAAAAA") ?? UUID(), action: .addLabel,
            targetID: belasting, origin: .ai, ruleName: "", quote: "", confidence: 1, isPreselected: false
        )
    }

    private func model(canEdit: Bool = true) throws -> ConfirmedDocumentModel {
        let connection = ServerConnection(
            urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn"
        )
        try store.save(connection, token: "tok")
        return ConfirmedDocumentModel(
            detail: detail(), persons: DocumentFixtures.persons, labels: DocumentFixtures.labels,
            documents: WorkspaceDocuments(workspaceID: UUID(), connection: connection, store: store, server: server),
            canEdit: canEdit,
            onRevoked: { [events] in events.add("revoked") },
            onMissingPairing: { [events] in events.add("missing") }
        )
    }

    private func workspaceTask(isDone: Bool) -> WorkspaceTask {
        WorkspaceTask(
            id: taskID, type: "pay", description: "Betaal de aanslag", deadline: nil, isDone: isDone,
            documentID: documentID, sender: "Belastingdienst"
        )
    }

    @Test func settingAddresseesReplacesTheDetail() async throws {
        let answer = detail(addressees: [stijn, anne], suggestions: [belastingSuggestion])
        server.onOrganise { _, _ in answer }
        let model = try model()

        await model.setAddressees([stijn, anne])

        #expect(server.calls.contains { call in
            guard case let .setAddressees(_, document, ids) = call else { return false }
            return document == documentID && Set(ids) == [stijn, anne]
        })
        #expect(model.detail == answer)
        #expect(model.organise.addresseeIDs == [stijn, anne])
        #expect(model.organise.openSuggestions(for: .addAddressee).isEmpty)
        #expect(model.changeError == nil)
    }

    @Test func settingLabelsSendsTheExactSet() async throws {
        let answer = detail(labels: [])
        server.onOrganise { _, _ in answer }
        let model = try model()

        await model.setLabels([])

        #expect(server.calls.contains { call in
            if case let .setLabels(_, _, ids) = call { ids.isEmpty } else { false }
        })
        #expect(model.organise.labelIDs.isEmpty)
    }

    @Test func aFailedChangeRestoresTheShownState() async throws {
        server.onOrganise { _, _ in throw ServerError.other("document_processing") }
        let model = try model()
        let before = (model.organise, model.detail)

        await model.setLabels([zorg, belasting])

        #expect(model.organise == before.0)
        #expect(model.detail == before.1)
        #expect(model.changeError == "Dit lukte niet. Probeer het opnieuw.")
    }

    @Test func acceptAddsTheLabelAndRemovesTheSuggestion() async throws {
        let answer = detail(labels: [zorg, belasting], suggestions: [anneSuggestion])
        server.onOrganise { _, _ in answer }
        let model = try model()

        await model.accept(belastingSuggestion)

        #expect(server.calls.contains { call in
            if case let .acceptSuggestion(_, document, id) = call {
                document == documentID && id == belastingSuggestion.id
            } else {
                false
            }
        })
        #expect(model.organise.labelIDs == [zorg, belasting])
        #expect(model.organise.openSuggestions(for: .addLabel).isEmpty)
        #expect(model.organise.openSuggestions(for: .addAddressee) == [anneSuggestion])
    }

    @Test func dismissOnlyRemovesTheSuggestion() async throws {
        let answer = detail(suggestions: [belastingSuggestion])
        server.onOrganise { _, _ in answer }
        let model = try model()

        await model.dismiss(anneSuggestion)

        #expect(server.calls.contains { call in
            if case let .dismissSuggestion(_, _, id) = call { id == anneSuggestion.id } else { false }
        })
        #expect(model.organise.addresseeIDs == [stijn])
        #expect(model.organise.openSuggestions(for: .addAddressee).isEmpty)
        #expect(model.organise.openSuggestions(for: .addLabel) == [belastingSuggestion])
    }

    @Test func tickingATaskCallsTheHook() async throws {
        let done = workspaceTask(isDone: true)
        let open = workspaceTask(isDone: false)
        server.onCompleteTask { _, _ in done }
        server.onReopenTask { _, _ in open }
        let model = try model()
        var hookCalls = 0
        model.onTasksChanged = { hookCalls += 1 }

        await model.setTask(taskID, done: true)

        #expect(server.calls.contains(.completeTask(Self.url, taskID)))
        #expect(model.tasks.first?.isDone == true)
        #expect(hookCalls == 1)

        await model.setTask(taskID, done: false)

        #expect(server.calls.contains(.reopenTask(Self.url, taskID)))
        #expect(model.tasks.first?.isDone == false)
        #expect(hookCalls == 2)
    }

    @Test func aFailedTickRestoresTheTaskWithoutTheHook() async throws {
        server.onCompleteTask { _, _ in throw ServerError.other("task_not_found") }
        let model = try model()
        var hookCalls = 0
        model.onTasksChanged = { hookCalls += 1 }

        await model.setTask(taskID, done: true)

        #expect(model.tasks.first?.isDone == false)
        #expect(hookCalls == 0)
        #expect(model.changeError == DocumentStrings.changeFailed)
    }

    @Test func aViewerCannotChangeAnything() async throws {
        let model = try model(canEdit: false)
        let before = (model.organise, model.detail)

        await model.setAddressees([anne])
        await model.setLabels([])
        await model.accept(belastingSuggestion)
        await model.dismiss(anneSuggestion)
        await model.setTask(taskID, done: true)
        let created = await model.createPerson(named: "Papa")

        #expect(!created)
        #expect(server.calls.isEmpty)
        #expect(model.organise == before.0)
        #expect(model.detail == before.1)
        #expect(model.tasks.first?.isDone == false)
    }

    @Test func aRevokedDeviceEndsTheSession() async throws {
        server.onOrganise { _, _ in throw ServerError.unauthorized }
        let model = try model()

        await model.setLabels([])

        #expect(events.all == ["revoked"])
        #expect(model.organise.labelIDs == [zorg])
    }

    @Test func aNewPersonIsAddedAsAddressee() async throws {
        let papa = Person(id: UUID(), displayName: "Papa", nameVariants: [], isArchived: false)
        server.onCreatePerson { _, _ in papa }
        let answer = detail(addressees: [stijn, papa.id])
        server.onOrganise { _, _ in answer }
        let model = try model()

        let created = await model.createPerson(named: " Papa ")

        #expect(created)
        #expect(model.persons.contains(papa))
        #expect(server.calls.contains { call in
            if case let .setAddressees(_, _, ids) = call { Set(ids) == [stijn, papa.id] } else { false }
        })
        #expect(model.organise.addresseeIDs == [stijn, papa.id])
    }
}

/// The review hands a confirmed letter to `ConfirmedDocumentModel` and reports that its tasks changed.
@MainActor
@Suite struct ReviewConfirmedTests {
    private let harness = ReviewHarness()

    init() {
        harness.answer { id in DocumentFixtures.detailWithSuggestions(id: id) }
        harness.server.onConfirm { _, id, _ in DocumentFixtures.detail(id: id, status: .done) }
    }

    @Test func confirmingCallsTheHookAndOpensTheConfirmedLetter() async throws {
        let model = try harness.model()
        var hookCalls = 0
        model.onTasksChanged = { hookCalls += 1 }
        await model.load()
        #expect(model.confirmed == nil)

        await model.confirm()

        #expect(hookCalls == 1)
        let confirmed = try #require(model.confirmed)
        #expect(confirmed.persons == DocumentFixtures.persons)
        #expect(confirmed.canEdit)
    }

    @Test func aTickInTheConfirmedLetterReachesTheReviewHook() async throws {
        let task = ConfirmedTask(
            id: UUID(), type: "pay", description: "Betaal", deadline: nil, deadlineSource: "manual",
            deadlineQuote: ""
        )
        harness.answer { id in DocumentFixtures.detail(id: id, status: .done, tasks: [task]) }
        let model = try harness.model()
        var hookCalls = 0
        model.onTasksChanged = { hookCalls += 1 }
        await model.load()
        let confirmed = try #require(model.confirmed)

        await confirmed.setTask(task.id, done: true)

        #expect(hookCalls == 1)
    }

    @Test func aFailedConfirmDoesNotCallTheHook() async throws {
        harness.server.onConfirm { _, _, _ in throw ServerError.other("validation_error") }
        let model = try harness.model()
        var hookCalls = 0
        model.onTasksChanged = { hookCalls += 1 }
        await model.load()

        await model.confirm()

        #expect(hookCalls == 0)
    }

    @Test func a1bServerHasNoConfirmedLetterModel() async throws {
        harness.server.onPersons { _ in throw ServerError.other("not_found") }
        harness.answer { id in DocumentFixtures.detail(id: id, status: .done) }
        let model = try harness.model()

        await model.load()

        #expect(model.state == .done)
        #expect(model.confirmed == nil)
    }
}
