import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// "Te doen": one list, each row saying what it needs, what needs the person first and what is on its way last.
@MainActor
@Suite struct DocumentsTodoListTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")

    private let workspaceID = UUID()
    private let store = ConnectionStore(secrets: InMemorySecretStore())
    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
    private let queue = FakeUploadQueue()

    private func model(canScan: Bool = true) throws -> DocumentsModel {
        let connection = ServerConnection(
            urls: [Self.url], caCertificateDER: nil, deviceID: UUID(), userName: "Stijn"
        )
        try store.save(connection, token: "tok")
        return DocumentsModel(
            documents: WorkspaceDocuments(
                workspaceID: workspaceID, connection: connection, store: store, server: server
            ),
            uploads: queue, canScan: canScan, camera: FakeScanCamera(.allowed), openSettings: {}, onRevoked: {},
            onMissingPairing: {}
        )
    }

    private nonisolated static func document(
        _ state: InboxState, status: DocumentStatus = .done, sender: String = "", minutes: Double = 0
    ) -> DocumentSummary {
        DocumentSummary(
            id: UUID(), clientID: UUID(), status: status, pageCount: 1,
            createdAt: Date(timeIntervalSince1970: 1_794_650_400 + minutes * 60), sender: sender, documentType: "",
            letterDate: nil, inboxState: state
        )
    }

    private func serve(_ documents: [DocumentSummary]) {
        server.onList { _, filter in
            guard let state = filter.inboxState else { return documents }
            return documents.filter { $0.inboxState == state }
        }
    }

    // MARK: What each row says

    @Test(arguments: [
        (DocumentStatus.needsReview, InboxState.review, DocumentsModel.RowStatus.needsReview),
        (.failed, .review, .failed),
        (.done, .unassigned, .needsName),
        (.processing, .new, .processing),
        (.done, .sorted, .done),
        (.unknown, .unassigned, .needsName),
        (.unknown, .sorted, .done)
    ])
    func aLetterSaysWhatItNeeds(status: DocumentStatus, state: InboxState, expected: DocumentsModel.RowStatus) {
        let document = Self.document(state, status: status)
        #expect(DocumentsModel.status(of: document) == expected)
    }

    @Test func theWordsAreThoseOfTheWeb() {
        typealias Status = DocumentsModel.RowStatus
        #expect(Status.needsReview.label == "Controleren")
        #expect(Status.failed.label == "Controleren")
        #expect(Status.needsName.label == "Naam kiezen")
        #expect(Status.processing.label == "Bezig…")
        #expect(Status.done.label == "Klaar")
        // A letter Brievie could not read is checked like any other, with the reason under it.
        #expect(Status.failed.note == "Brievie kon deze brief niet goed lezen.")
        #expect(Status.processing.note == "Je hoeft niets te doen.")
        #expect(Status.needsReview.note == nil)
    }

    @Test func everyStatusHasASymbolAndWords() {
        typealias Status = DocumentsModel.RowStatus
        let all: [Status] = [
            .waitingForUpload, .uploading(progress: 0.5), .uploadFailed(message: "x"), .processing, .needsReview,
            .failed, .needsName, .done
        ]
        for status in all {
            #expect(!status.label.isEmpty)
            #expect(!status.iconName.isEmpty)
        }
        // Never colour alone: the two kinds of "Controleren" have the same word, the reason is in the note.
        #expect(Set(all.map(\.iconName)).count >= 6)
    }

    @Test func theRowReadsItsStatusAndNoteAloud() async throws {
        let failed = Self.document(.review, status: .failed, sender: "CAK")
        serve([failed])
        let model = try model()

        await model.load()

        let label = try #require(model.rows.first?.accessibilityLabel)
        #expect(label.contains("CAK"))
        #expect(label.contains("Controleren"))
        #expect(label.contains("Brievie kon deze brief niet goed lezen."))
    }

    // MARK: One list, in order

    @Test func whatNeedsThePersonComesFirstAndWhatIsOnItsWayLast() async throws {
        let oldReview = Self.document(.review, status: .needsReview, minutes: 1)
        let newName = Self.document(.unassigned, minutes: 5)
        let failed = Self.document(.review, status: .failed, minutes: 3)
        let reading = Self.document(.new, status: .processing, minutes: 9)
        let uploading = FakeUploadQueue.item(
            workspaceID: workspaceID, createdAt: Date(timeIntervalSince1970: 1_794_650_400 + 600)
        )
        let uploadFailed = FakeUploadQueue.item(
            workspaceID: workspaceID, state: .failed, failureCode: "untrusted",
            createdAt: Date(timeIntervalSince1970: 1_794_650_400 + 120)
        )
        queue.set([uploading, uploadFailed])
        serve([oldReview, newName, failed, reading])
        let model = try model()

        await model.load()

        // Needs the person, newest first (a failed upload too: it waits for "Opnieuw proberen" or "Verwijderen");
        // then what is on its way, newest first: the scan still on the phone and the letter being read.
        #expect(model.rows.map(\.id) == [
            newName.id, failed.id, uploadFailed.id, oldReview.id, uploading.id, reading.id
        ])
        #expect(model.rows.map(\.status.label) == [
            "Naam kiezen", "Controleren", "Upload mislukt", "Controleren", "Wacht op verbinding", "Bezig…"
        ])
    }

    @Test func aFailedUploadStaysRetryableInTheList() async throws {
        let failed = FakeUploadQueue.item(workspaceID: workspaceID, state: .failed, failureCode: "payload_too_large")
        queue.set([failed])
        let model = try model()

        await model.load()

        let row = try #require(model.rows.first)
        #expect(row.documentID == nil)
        #expect(row.status.canRetryUpload)
        #expect(row.status.canDelete)
        await model.retryUpload(failed.id)
        #expect(queue.retried == [failed.id])
    }

    @Test func allPostKeepsTheOrderOfTime() async throws {
        let review = Self.document(.review, status: .needsReview, minutes: 1)
        let sorted = Self.document(.sorted, minutes: 5)
        let reading = Self.document(.new, status: .processing, minutes: 3)
        serve([review, sorted, reading])
        let model = try model()

        await model.select(.all)

        #expect(model.rows.map(\.id) == [sorted.id, reading.id, review.id])
        #expect(model.summary == nil)
    }

    // MARK: The line above and the line under the list

    @Test func theLineAboveCountsEachKindInTheWordsOfTheRows() async throws {
        let failedUpload = FakeUploadQueue.item(workspaceID: workspaceID, state: .failed)
        let waiting = FakeUploadQueue.item(workspaceID: workspaceID)
        queue.set([failedUpload, waiting])
        serve([
            Self.document(.review, status: .needsReview), Self.document(.review, status: .failed),
            Self.document(.unassigned), Self.document(.new, status: .processing)
        ])
        let model = try model()

        await model.load()

        #expect(model.summary == "Controleren: 2 · Naam kiezen: 1 · Upload mislukt: 1 · Bezig: 2")
    }

    @Test func theLineAboveSaysWhenOnlyTheNewestAreShown() async throws {
        let reviews = (0..<200).map { _ in Self.document(.review, status: .needsReview) }
        serve(reviews)
        server.onInboxCounts { _ in InboxCounts(new: 0, review: 212, unassigned: 0) }
        let model = try model()

        await model.load()

        #expect(model.summary == "Controleren: 212 (de nieuwste 200)")
    }

    @Test func theLineUnderTheListSaysWhatThePlaceIsFor() async throws {
        serve([Self.document(.review, status: .needsReview), Self.document(.sorted)])
        let model = try model()

        await model.load()
        #expect(model.footer == """
            Brieven waar jij nog iets mee moet doen. Al je brieven, ook de afgehandelde, staan bij Alle post.
            """)

        await model.select(.all)
        #expect(model.footer == "Al je brieven, ook de afgehandelde. Wat nog op jou wacht, staat bij Te doen.")
    }

    // MARK: Nothing to do

    @Test func anEmptyListSaysYouAreDoneAndWhereTheRestIs() async throws {
        serve([Self.document(.sorted)])
        let model = try model()

        await model.load()

        #expect(model.rows.isEmpty)
        #expect(model.summary == nil)
        #expect(model.footer == nil)
        #expect(model.emptyText == "Je bent klaar. Er is niets te doen.")
        #expect(model.emptyHint == """
            Een nieuwe brief scan je met de knop + bovenaan. Eerdere brieven vind je bij Alle post.
            """)
        #expect(model.emptyOffersAllPost)
    }

    @Test func aViewerIsNotToldToScan() async throws {
        serve([])
        let model = try model(canScan: false)

        await model.load()

        #expect(model.emptyHint == "Eerdere brieven vind je bij Alle post.")
    }

    @Test func otherPlacesKeepTheirOwnEmptyText() async throws {
        serve([])
        let model = try model()

        await model.select(.all)

        #expect(model.emptyText == DocumentStrings.empty)
        #expect(model.emptyHint == nil)
        #expect(!model.emptyOffersAllPost)
    }

    // MARK: Names of the places

    @Test func thePlacesAreTeDoenAndAllePost() async throws {
        let model = try model()
        await model.load()

        #expect(model.scopeTitles.prefix(2).map(\.1) == ["Te doen", "Alle post"])
        #expect(model.scopeTitle == "Te doen")
    }

    @Test func aLetterWithoutSenderIsNamedByWhereItIs() async throws {
        let reading = Self.document(.new, status: .processing, minutes: 2)
        let read = Self.document(.review, status: .needsReview, minutes: 1)
        let item = FakeUploadQueue.item(workspaceID: workspaceID)
        queue.set([item])
        serve([reading, read])
        let model = try model()

        await model.load()

        // A letter to check has no sender in the list yet: it is named by the time it came in.
        let arrived = String(
            format: DocumentStrings.arrivedFormat, read.createdAt.formatted(date: .omitted, time: .shortened)
        )
        #expect(model.rows.map(\.title) == [arrived, "Nieuwe brief", "Nieuwe brief"])
    }
}
