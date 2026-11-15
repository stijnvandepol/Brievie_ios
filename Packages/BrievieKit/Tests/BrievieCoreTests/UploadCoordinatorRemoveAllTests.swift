@testable import BrievieCore
import BrievieScan
import Foundation
import Testing

/// Unpairing empties the queue: every upload stopped, every file gone.
@Suite struct UploadCoordinatorRemoveAllTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "queue-\(UUID().uuidString)")
    private let transport = FakeUploadTransport()
    private let workspaceID = UUID()
    private let deviceA = UUID()

    private func coordinator() throws -> UploadCoordinator {
        let url = try #require(URL(string: "https://brievie.local"))
        let connection = ServerConnection(urls: [url], caCertificateDER: nil, deviceID: deviceA, userName: "Stijn")
        return UploadCoordinator(
            store: UploadQueueStore(directory: directory),
            transport: transport,
            connection: { (connection, "token-a") },
            onRevoked: { _ in }
        )
    }

    private var page: [ScannedPage] { [ScannedPage(jpeg: Data([0xFF, 0xD8, 0xFF, 1]), text: "tekst")] }

    private func finished(_ item: UploadItem, _ outcome: UploadOutcome) -> UploadEvent {
        let attempt = transport.starts.last { $0.itemID == item.id }?.attemptID ?? UUID()
        return .finished(itemID: item.id, deviceID: deviceA, attemptID: attempt, outcome: outcome)
    }

    private func entries() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []).sorted()
    }

    @Test func removeAllCancelsEveryUploadAndLeavesNoFiles() async throws {
        let uploads = try coordinator()
        let first = try await uploads.enqueue(pages: page, workspaceID: workspaceID)
        let second = try await uploads.enqueue(pages: page, workspaceID: workspaceID)
        // What an interrupted enqueue and an unreadable item leave behind goes too.
        let leftover = directory.appending(path: ".incoming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        let unreadable = directory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: unreadable.appending(path: "item.json"))

        try await uploads.removeAll()

        #expect(Set(transport.cancelled) == [first.id, second.id])
        #expect(await uploads.items().isEmpty)
        #expect(entries().isEmpty)
        // A late event of a cancelled upload finds nothing to bring back.
        await uploads.handle(finished(first, .status(201, code: nil)))
        #expect(entries().isEmpty)
    }

    @Test func removeAllOnAnEmptyQueueSucceeds() async throws {
        try await coordinator().removeAll()

        #expect(entries().isEmpty)
    }

    @Test func removeAllReportsAQueueThatCouldNotBeDeleted() async throws {
        let uploads = try coordinator()
        _ = try await uploads.enqueue(pages: page, workspaceID: workspaceID)
        let path = directory.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path) }

        await #expect(throws: (any Error).self) {
            try await uploads.removeAll()
        }
        #expect(entries().count == 1)
    }
}
