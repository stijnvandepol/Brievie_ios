@testable import BrievieCore
import Foundation
import Testing

/// The reading calls through the seam: "not supported" from an older server, and "Alles gelezen" in parts of 200.
@Suite struct WorkspaceDocumentsReadingTests {
    private static let local = URL(string: "https://brievie.local") ?? URL(fileURLWithPath: "/")

    private let store = ConnectionStore(secrets: InMemorySecretStore())
    private let server = FakeDocumentServer { _, id in DocumentFixtures.detail(id: id) }
    private let connection = ServerConnection(
        urls: [WorkspaceDocumentsReadingTests.local], caCertificateDER: nil, deviceID: UUID(), userName: "Jij"
    )

    private func documents() throws -> WorkspaceDocuments {
        try store.save(connection, token: "tok")
        return WorkspaceDocuments(workspaceID: UUID(), connection: connection, store: store, server: server)
    }

    @Test func anOlderServerDoesNotSupportTheMenuOrReading() async throws {
        server.onMenuCounts { _ in throw ServerError.other("http_404") }
        server.onMarkRead { _, _ in throw ServerError.other("http_404") }

        let documents = try documents()

        await #expect(throws: DocumentsError.notSupported) { try await documents.menuCounts() }
        await #expect(throws: DocumentsError.notSupported) { try await documents.markRead(UUID()) }
    }

    @Test func manyLettersAreMarkedInPartsOfTwoHundred() async throws {
        let ids = (0..<450).map { _ in UUID() }

        let marked = try await documents().markRead(ids)

        let parts = server.calls.compactMap { call -> [UUID]? in
            if case let .markManyRead(_, part) = call { return part }
            return nil
        }
        #expect(parts.map(\.count) == [200, 200, 50])
        #expect(parts.flatMap { $0 } == ids)
        #expect(marked == 450)
    }
}
