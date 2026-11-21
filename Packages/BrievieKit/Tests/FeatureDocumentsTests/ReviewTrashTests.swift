import BrievieCore
@testable import FeatureDocuments
import Foundation
import Testing

/// "Verwijderen" on a letter: asked first, one request, and a letter that is already in the trash.
@MainActor
@Suite struct ReviewTrashTests {
    private static let url = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")
    private let harness = ReviewHarness()

    private var trashCalls: Int {
        harness.server.calls.count { if case .trash = $0 { true } else { false } }
    }

    @Test func deleteAsksFirstThenTrashesAndReportsTheLetter() async throws {
        let model = try harness.model(trashAvailable: true)
        let reported = LockedList()
        model.onTrashed = { reported.append($0.uuidString) }
        await model.load()
        #expect(model.canTrash)

        model.askToTrash()
        #expect(model.asksToTrash)
        #expect(trashCalls == 0)

        await model.trash()

        #expect(harness.server.calls.last == .trash(Self.url, harness.documentID))
        #expect(trashCalls == 1)
        #expect(reported.values == [harness.documentID.uuidString])
        #expect(model.state == .trashed)
        #expect(!model.asksToTrash)
    }

    @Test func aViewerOrAServerWithoutTrashHasNoDelete() async throws {
        let viewer = try harness.model(canEdit: false, trashAvailable: true)
        await viewer.load()
        #expect(!viewer.canTrash)

        let older = try harness.model(trashAvailable: false)
        await older.load()
        #expect(!older.canTrash)

        await older.trash()
        #expect(trashCalls == 0)
    }

    @Test func aLetterBeingReadCannotBeDeletedYet() async throws {
        harness.answer { id in DocumentFixtures.detail(id: id, status: .processing) }
        let model = try harness.model(trashAvailable: true)

        await model.load()

        #expect(model.state == .processing)
        #expect(!model.canTrash)
    }

    @Test func aConfirmedLetterCanBeDeleted() async throws {
        harness.answer { id in DocumentFixtures.detail(id: id, status: .done) }
        let model = try harness.model(trashAvailable: true)

        await model.load()

        #expect(model.state == .done)
        #expect(model.canTrash)
    }

    @Test func aLetterInTheTrashSaysSo() async throws {
        harness.server.onDetail { _, _ in throw ServerError.other("document_in_trash") }
        let model = try harness.model(trashAvailable: true)

        await model.load()

        #expect(model.state == .inTrash)
        #expect(!model.canTrash)
        #expect(DocumentStrings.inTrash == "Deze brief staat in de prullenbak.")
    }

    @Test func aForbiddenDeleteShowsTheSentence() async throws {
        harness.server.onTrash { _, _ in throw ServerError.other("forbidden") }
        let model = try harness.model(trashAvailable: true)
        await model.load()

        await model.trash()

        #expect(model.saveError == "Je mag dit niet doen in deze werkruimte.")
        #expect(model.state == .review)
    }

    @Test func aBusyLetterSaysSo() async throws {
        harness.server.onTrash { _, _ in throw ServerError.other("document_processing") }
        let model = try harness.model(trashAvailable: true)
        await model.load()

        await model.trash()

        #expect(model.saveError == DocumentStrings.busy)
    }

    @Test func aSecondTapWhileTrashingSendsNothing() async throws {
        let gated = GatedDocumentServer(harness.server)
        gated.close(gate: .trash)
        let model = try harness.model(trashAvailable: true, server: gated)
        await model.load()

        let first = Task { await model.trash() }
        while !gated.isWaiting(gate: .trash) { await Task.yield() }
        #expect(model.isSaving)
        await model.trash()
        gated.open(gate: .trash)
        await first.value

        #expect(trashCalls == 1)
        #expect(model.state == .trashed)
    }

    @Test func leavingTheForegroundClosesTheQuestion() async throws {
        let model = try harness.model(trashAvailable: true)
        await model.load()
        model.askToTrash()

        model.sceneDidChange(isActive: false)

        #expect(!model.asksToTrash)
        #expect(trashCalls == 0)
    }
}
