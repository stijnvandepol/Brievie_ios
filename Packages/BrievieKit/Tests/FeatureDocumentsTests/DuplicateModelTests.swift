import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// The compare screen of a pair: what is marked, which letter is kept, the twin switch, one request per tap, and
/// a pair that was decided or removed elsewhere.
@MainActor
@Suite struct DuplicateModelTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")

    private let store = ConnectionStore(secrets: InMemorySecretStore())
    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
    private let events = EventLog()
    private let first = DocumentFixtures.summary(sender: "Gemeente Voorbeelddorp")
    private let second = DocumentFixtures.summary(sender: "Gemeente Voorbeelddorp")

    private func pair(
        differences: [DuplicateDifference] = [], twins: [TaskTwin] = [], canMerge: Bool = true
    ) -> DuplicatePair {
        DocumentFixtures.pair(
            first: first, second: second, suggestedKeep: second.id, differences: differences, twins: twins,
            canMerge: canMerge
        )
    }

    private func model(
        _ pair: DuplicatePair, canEdit: Bool = true, server documentServer: (any DocumentServer)? = nil
    ) throws -> DuplicateModel {
        let connection = ServerConnection(
            urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn"
        )
        try store.save(connection, token: "tok")
        server.onDuplicate { _, _ in pair }
        return DuplicateModel(
            pairID: pair.id,
            documents: WorkspaceDocuments(
                workspaceID: UUID(), connection: connection, store: store, server: documentServer ?? server
            ),
            canEdit: canEdit, persons: [], labels: [],
            onMerged: { [events] in events.add("merged \($0.uuidString)") },
            onDismissed: { [events] in events.add("dismissed") },
            onDecidedElsewhere: { [events] in events.add("decided") },
            onRevoked: { [events] in events.add("revoked") },
            onMissingPairing: { [events] in events.add("missing") },
            locale: Locale(identifier: "nl_NL")
        )
    }

    private var mergeCalls: [FakeDocumentServer.Call] {
        server.calls.filter { if case .merge = $0 { true } else { false } }
    }

    private func twin(openOn id: UUID, doneOn done: UUID) -> TaskTwin {
        TaskTwin(doneDocumentID: done, openDocumentID: id, type: "pay", description: "Betaal de aanslag")
    }

    @Test func aTwinWithoutADescriptionIsNamedByItsType() async throws {
        let twin = TaskTwin(doneDocumentID: second.id, openDocumentID: first.id, type: "pay", description: "")
        let model = try model(pair(twins: [twin]))
        await model.load()
        model.keepID = first.id

        #expect(model.twinNotes == ["Op de andere scan is '\(DocumentTypes.taskTypeLabel("pay"))' al afgerond."])
        #expect(!(model.twinNotes.first?.contains("''") ?? true))
    }

    @Test func theSuggestedLetterIsPreselected() async throws {
        let model = try model(pair())

        await model.load()

        #expect(model.state == .loaded)
        #expect(model.keepID == second.id)
        #expect(model.pair?.id == model.pairID)
        #expect(model.details[first.id] != nil)
        #expect(model.details[second.id] != nil)
        #expect(server.calls.contains(.page(Self.url, first.id, 1)))
        #expect(server.calls.contains(.page(Self.url, second.id, 1)))
    }

    @Test func differingFieldsAreMarkedAndUncertainOnesSaySo() async throws {
        let model = try model(pair(differences: [
            DuplicateDifference(field: .sender, first: "Gemeente", second: "CAK", isUncertain: false),
            DuplicateDifference(field: .amount, first: "120.50", second: "125.00", isUncertain: true)
        ]))

        await model.load()

        let rows = Dictionary(uniqueKeysWithValues: model.rows.map { ($0.title, $0) })
        #expect(rows["Afzender"]?.mark == .differs)
        #expect(rows["Bedrag"]?.mark == .mayDiffer)
        #expect(rows["Pagina's"]?.mark == nil)
        #expect(rows["Afzender"]?.accessibilityLabel.hasSuffix("Verschilt") == true)
        #expect(rows["Bedrag"]?.accessibilityLabel.hasSuffix("Verschilt misschien (slecht leesbaar)") == true)
        #expect(
            rows["Pagina's"]?.accessibilityLabel == "Pagina's. Brief 1: 1 pagina. Brief 2: 1 pagina."
        )
    }

    @Test func amountRowsAppearOnlyWhenTheyDiffer() async throws {
        let model = try model(pair())

        await model.load()

        let titles = model.rows.map(\.title)
        #expect(!titles.contains("Bedrag"))
        #expect(!titles.contains("Factuurnummer"))
        #expect(!titles.contains("Kenmerk"))
        #expect(titles == ["Afzender", "Soort", "Datum", "Pagina's", "Labels", "Op naam van", "Taken"])
    }

    @Test func theTwinSwitchFollowsTheKeptLetter() async throws {
        let model = try model(pair(twins: [twin(openOn: first.id, doneOn: second.id)]))
        await model.load()

        model.keepID = first.id
        #expect(model.twinNotes == ["Op de andere scan is 'Betaal de aanslag' al afgerond."])

        model.keepID = second.id
        #expect(model.twinNotes.isEmpty)
    }

    @Test func askingToMergeTurnsTheTwinSwitchOnAgain() async throws {
        let model = try model(pair(twins: [twin(openOn: first.id, doneOn: second.id)]))
        await model.load()
        model.askToMerge()
        model.completeTwinTasks = false
        model.asksToMerge = false

        model.askToMerge()

        #expect(model.asksToMerge)
        #expect(model.completeTwinTasks)
    }

    @Test func mergeSendsTheChoiceAndReportsTheOtherLetter() async throws {
        let pair = pair(twins: [twin(openOn: second.id, doneOn: first.id)])
        let model = try model(pair)
        await model.load()
        model.keepID = second.id
        model.askToMerge()
        model.completeTwinTasks = false

        await model.merge()

        #expect(mergeCalls == [.merge(Self.url, pair.id, keep: second.id, completeTwinTasks: false)])
        #expect(events.all == ["merged \(first.id.uuidString)"])
        #expect(model.state == .finished)
        #expect(!model.asksToMerge)
    }

    @Test func withoutATwinTheMergeSendsTheDefault() async throws {
        let pair = pair(twins: [twin(openOn: second.id, doneOn: first.id)])
        let model = try model(pair)
        await model.load()
        // The twin is open on the letter that goes: no switch, so the server's default.
        model.keepID = first.id
        model.askToMerge()
        model.completeTwinTasks = false

        await model.merge()

        #expect(mergeCalls == [.merge(Self.url, pair.id, keep: first.id, completeTwinTasks: true)])
        #expect(events.all == ["merged \(second.id.uuidString)"])
    }

    @Test func aSecondTapWhileMergingSendsNothing() async throws {
        let gated = GatedDocumentServer(server)
        gated.close(gate: .merge)
        let model = try model(pair(), server: gated)
        await model.load()

        let firstTap = Task { await model.merge() }
        while !gated.isWaiting(gate: .merge) { await Task.yield() }
        #expect(model.isSaving)
        await model.merge()
        await model.dismiss()
        gated.open(gate: .merge)
        await firstTap.value

        #expect(mergeCalls.count == 1)
        #expect(!server.calls.contains { if case .dismissDuplicate = $0 { true } else { false } })
        #expect(model.state == .finished)
    }

    @Test func dismissReportsAndFinishes() async throws {
        let pair = pair()
        let model = try model(pair)
        await model.load()

        await model.dismiss()

        #expect(server.calls.contains(.dismissDuplicate(Self.url, pair.id)))
        #expect(events.all == ["dismissed"])
        #expect(model.state == .finished)
    }

    @Test func visibilityDiffersHidesTheMergeAndExplains() async throws {
        server.onMerge { _, _, _, _ in throw ServerError.other("duplicate_visibility_differs") }
        let model = try model(pair())
        await model.load()
        #expect(model.canMerge)
        #expect(model.blockedNote == nil)

        await model.merge()

        #expect(!model.canMerge)
        #expect(model.blockedNote == Self.visibilitySentence)
        #expect(model.state == .loaded)
        #expect(events.all.isEmpty)
    }

    @Test func aPairTheServerCannotMergeShowsOnlyDismiss() async throws {
        let model = try model(pair(canMerge: false))

        await model.load()
        await model.merge()

        #expect(!model.canMerge)
        #expect(model.blockedNote == Self.visibilitySentence)
        #expect(mergeCalls.isEmpty)
        #expect(model.canDecide)
    }

    @Test func alreadyDecidedSaysSoAndFinishes() async throws {
        server.onDismissDuplicate { _, _ in throw ServerError.other("duplicate_not_open") }
        let model = try model(pair())
        await model.load()

        await model.dismiss()

        #expect(model.message == "Over deze twee brieven is al gekozen.")
        #expect(events.all == ["decided"])
        #expect(model.state == .finished)
    }

    @Test func aMergeWhileTheLetterIsReadShowsTheBusyMessage() async throws {
        server.onMerge { _, _, _, _ in throw ServerError.other("document_processing") }
        let model = try model(pair())
        await model.load()

        await model.merge()

        #expect(model.message == "Deze brief wordt nog gelezen. Probeer het zo opnieuw.")
        #expect(model.state == .loaded)
        #expect(model.canMerge)
    }

    @Test func aGonePairSaysSo() async throws {
        let model = try model(pair())
        server.onDuplicate { _, _ in throw ServerError.other("duplicate_not_found") }

        await model.load()

        #expect(model.state == .gone(message: "Deze dubbele brieven zijn er niet (meer)."))
    }

    @Test func aViewerSeesNoChoices() async throws {
        let model = try model(pair(), canEdit: false)
        await model.load()

        #expect(!model.canMerge)
        #expect(!model.canDecide)
        #expect(model.blockedNote == nil)
        await model.merge()
        await model.dismiss()

        #expect(mergeCalls.isEmpty)
        #expect(!server.calls.contains { if case .dismissDuplicate = $0 { true } else { false } })
    }

    @Test func leavingTheForegroundClosesTheMergeSheet() async throws {
        let model = try model(pair())
        await model.load()
        model.askToMerge()

        model.sceneDidChange(isActive: false)

        #expect(!model.asksToMerge)
        #expect(mergeCalls.isEmpty)
    }

    @Test func aRevokedSessionEnds() async throws {
        server.onMerge { _, _, _, _ in throw ServerError.unauthorized }
        let model = try model(pair())
        await model.load()

        await model.merge()

        #expect(events.all == ["revoked"])
    }

    @Test func theReaderShowsTheTappedLetter() async throws {
        let model = try model(pair())
        await model.load()

        model.openReader(second.id)

        #expect(model.reader?.documentID == second.id)
        #expect(model.reader?.pages[1] != nil)
        model.reader?.closeReader()
        #expect(model.reader == nil)
    }

    @Test func compareCatalogAndCodeAgree() throws {
        for (key, resolved) in DocumentStrings.duplicates {
            #expect(try CatalogParity.dutchValue(forKey: key, target: "FeatureDocuments") == resolved, "\(key)")
        }
    }

    private static let visibilitySentence = """
        Deze twee brieven zijn niet voor dezelfde mensen zichtbaar. Daarom kun je ze niet samenvoegen. \
        Kies 'Het zijn twee brieven', of laat ze eerst voor dezelfde mensen zichtbaar zijn.
        """
}
