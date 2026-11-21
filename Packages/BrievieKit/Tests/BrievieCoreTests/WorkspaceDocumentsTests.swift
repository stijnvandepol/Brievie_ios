@testable import BrievieCore
import Foundation
import Testing

@Suite struct WorkspaceDocumentsTests {
    private static let local = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")
    private static let remote = URL(string: "https://brievie.example.nl") ?? URL(fileURLWithPath: "/")
    private static let documentID = UUID()

    private let store = ConnectionStore(secrets: InMemorySecretStore())
    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
    private let workspaceID = UUID()
    private let connection = ServerConnection(
        urls: [WorkspaceDocumentsTests.local, WorkspaceDocumentsTests.remote], caCertificateDER: nil,
        deviceID: UUID(), userName: "Stijn"
    )

    private func documents(paired: Bool = true) throws -> WorkspaceDocuments {
        if paired { try store.save(connection, token: "tok") }
        return WorkspaceDocuments(workspaceID: workspaceID, connection: connection, store: store, server: server)
    }

    @Test func listUsesTheFirstReachableAddressAndTheStoredToken() async throws {
        let summary = DocumentFixtures.summary()
        server.onList { url in
            if url == Self.local { throw ServerError.unreachable }
            return [summary]
        }

        let result = try await documents().list()

        #expect(result == [summary])
        #expect(server.calls == [.list(Self.local, .all), .list(Self.remote, .all)])
        #expect(server.tokens == ["tok", "tok"])
    }

    @Test func allAddressesUnreachable() async throws {
        server.onList { _ in throw ServerError.unreachable }

        await #expect(throws: DocumentsError.unreachable) { try await documents().list() }
    }

    @Test func untrustedServerIsNotVerified() async throws {
        server.onList { _ in throw ServerError.untrusted }

        await #expect(throws: DocumentsError.notVerified) { try await documents().list() }
        #expect(server.calls.count == 2)
    }

    @Test func revokedDeviceStopsAtOnce() async throws {
        server.onList { _ in throw ServerError.unauthorized }

        await #expect(throws: DocumentsError.revoked) { try await documents().list() }
        #expect(server.calls == [.list(Self.local, .all)])
    }

    @Test func aForeign401TriesTheNextAddressAndIsNoRevocation() async throws {
        let summary = DocumentFixtures.summary()
        server.onList { url in
            if url == Self.local { throw ServerError.other("http_401") }
            return [summary]
        }

        let result = try await documents().list()

        #expect(result == [summary])
        #expect(server.calls == [.list(Self.local, .all), .list(Self.remote, .all)])
    }

    @Test func aForeign401OnEveryAddressIsAFailureNotARevocation() async throws {
        server.onList { _ in throw ServerError.other("http_401") }

        await #expect(throws: DocumentsError.failed) { try await documents().list() }
        #expect(server.calls.count == 2)
    }

    @Test func missingPairingIsReported() async throws {
        await #expect(throws: DocumentsError.missingPairing) { try await documents(paired: false).list() }
        #expect(server.calls.isEmpty)
    }

    @Test(arguments: [
        ("document_not_found", DocumentsError.notFound),
        ("page_not_found", DocumentsError.notFound),
        ("workspace_not_found", DocumentsError.notFound),
        ("document_not_reviewable", DocumentsError.conflict),
        ("document_not_failed", DocumentsError.conflict),
        ("validation_error", DocumentsError.invalid),
        ("person_not_found", DocumentsError.notFound),
        ("label_not_found", DocumentsError.notFound),
        ("suggestion_not_found", DocumentsError.notFound),
        ("person_exists", DocumentsError.nameTaken),
        ("document_processing", DocumentsError.busy),
        ("http_500", DocumentsError.failed)
    ])
    func serverVerdictsAreSorted(code: String, expected: DocumentsError) async throws {
        server.onDetail { _, _ in throw ServerError.other(code) }

        await #expect(throws: expected) { try await documents().detail(Self.documentID) }
        // The server answered: another address would say the same.
        #expect(server.calls.count == 1)
    }

    @Test func cancellationIsNotAFailure() async throws {
        server.onList { _ in throw CancellationError() }

        await #expect(throws: DocumentsError.cancelled) { try await documents().list() }
    }

    @Test func everyCallGoesThroughTheSameRules() async throws {
        let review = ConfirmedReview(
            sender: "CAK", documentType: "bill", letterDate: nil, summary: "", summaryByAI: false, tasks: []
        )
        let all = try documents()

        _ = try await all.detail(Self.documentID)
        _ = try await all.pageImage(Self.documentID, index: 2)
        _ = try await all.confirm(Self.documentID, review: review)
        _ = try await all.retryProcessing(Self.documentID)

        #expect(server.calls == [
            .detail(Self.local, Self.documentID),
            .page(Self.local, Self.documentID, 2),
            .confirm(Self.local, Self.documentID, review),
            .retry(Self.local, Self.documentID)
        ])
    }

    @Test func organiseCallsGoThroughTheSameRules() async throws {
        let person = UUID()
        let label = UUID()
        let suggestion = UUID()
        let filter = DocumentFilter(inboxState: .unassigned, personID: person)
        server.onCreatePerson { _, name in
            Person(id: person, displayName: name, nameVariants: [], isArchived: false)
        }
        let all = try documents()

        _ = try await all.list(filter: filter)
        _ = try await all.persons()
        let created = try await all.createPerson(named: "Stijn")
        _ = try await all.labels()
        _ = try await all.setAddressees([person], document: Self.documentID)
        _ = try await all.setLabels([label], document: Self.documentID)
        _ = try await all.acceptSuggestion(suggestion, document: Self.documentID)
        _ = try await all.dismissSuggestion(suggestion, document: Self.documentID)

        #expect(created.displayName == "Stijn")
        #expect(server.calls == [
            .list(Self.local, filter),
            .persons(Self.local),
            .createPerson(Self.local, "Stijn"),
            .labels(Self.local),
            .setAddressees(Self.local, Self.documentID, [person]),
            .setLabels(Self.local, Self.documentID, [label]),
            .acceptSuggestion(Self.local, Self.documentID, suggestion),
            .dismissSuggestion(Self.local, Self.documentID, suggestion)
        ])
        #expect(server.tokens == Array(repeating: "tok", count: 8))
    }

    @Test func inboxCountsGoThroughTheSameRules() async throws {
        server.onInboxCounts { url in
            if url == Self.local { throw ServerError.unreachable }
            return InboxCounts(new: 1, review: 2, unassigned: 3)
        }

        let counts = try await documents().inboxCounts()

        #expect(counts == InboxCounts(new: 1, review: 2, unassigned: 3))
        #expect(server.calls == [.inboxCounts(Self.local), .inboxCounts(Self.remote)])
        #expect(server.tokens == ["tok", "tok"])
    }

    @Test func theFakeCountsWhatItsListHoldsByDefault() async throws {
        server.onList { _, filter in
            filter == .all ? [
                DocumentFixtures.summary(status: .needsReview, inboxState: .review),
                DocumentFixtures.summary(status: .done, inboxState: .unassigned),
                DocumentFixtures.summary(status: .done, inboxState: .sorted)
            ] : []
        }

        let counts = try await documents().inboxCounts()

        #expect(counts == InboxCounts(new: 0, review: 1, unassigned: 1))
    }

    @Test func organiseFailuresAreSortedToo() async throws {
        server.onPersons { url in
            if url == Self.local { throw ServerError.unreachable }
            throw ServerError.other("person_exists")
        }

        await #expect(throws: DocumentsError.nameTaken) { try await documents().persons() }
        #expect(server.calls == [.persons(Self.local), .persons(Self.remote)])
    }

    @Test func trashCallsGoThroughTheSameRules() async throws {
        let id = Self.documentID
        server.onTrash { url, id in
            if url == Self.local { throw ServerError.unreachable }
            return DocumentFixtures.trashed(id: id, sender: "CAK", by: "Anna")
        }

        let trashed = try await documents().trash(id)
        let restored = try await documents().restore(id)
        let list = try await documents().trashList()

        #expect(trashed.id == id)
        #expect(trashed.trashedByName == "Anna")
        #expect(restored.summary.id == id)
        #expect(list == TrashList(items: [], retentionDays: 30, total: 0))
        #expect(server.calls == [
            .trash(Self.local, id), .trash(Self.remote, id), .restore(Self.local, id), .trashList(Self.local)
        ])
    }

    @Test func aTrashedLetterAndAForbiddenChangeAreTheirOwnErrors() async throws {
        server.onDetail { _, _ in throw ServerError.other("document_in_trash") }
        server.onRestore { _, _ in throw ServerError.other("forbidden") }

        await #expect(throws: DocumentsError.inTrash) { try await documents().detail(Self.documentID) }
        await #expect(throws: DocumentsError.forbidden) { try await documents().restore(Self.documentID) }
    }
}
