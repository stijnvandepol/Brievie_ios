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
        #expect(server.calls == [.list(Self.local), .list(Self.remote)])
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
        #expect(server.calls == [.list(Self.local)])
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
}
