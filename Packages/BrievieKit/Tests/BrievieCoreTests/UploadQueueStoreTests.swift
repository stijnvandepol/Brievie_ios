@testable import BrievieCore
import BrievieScan
import Foundation
import Testing

@Suite struct UploadQueueStoreTests {
    // With a space, like the app's real "Application Support": a percent-encoded path would not be found.
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "Application Support \(UUID().uuidString)/Uploads")
    private let workspaceID = UUID()
    private let deviceID = UUID()

    private func pages(_ count: Int) -> [ScannedPage] {
        (1...count).map { ScannedPage(jpeg: Data([0xFF, 0xD8, 0xFF, UInt8($0)]), text: "pagina \($0)") }
    }

    private func entries() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? [])
            .sorted()
    }

    @Test func enqueuedItemSurvivesARelaunch() async throws {
        let store = UploadQueueStore(directory: directory)

        let item = try await store.enqueue(pages: pages(2), workspaceID: workspaceID, deviceID: deviceID)

        #expect(item.state == .waiting)
        #expect(item.attempt == 0)
        #expect(item.urlIndex == 0)
        #expect(item.pageCount == 2)
        #expect(item.workspaceID == workspaceID)
        #expect(item.deviceID == deviceID)

        let relaunched = UploadQueueStore(directory: directory)
        #expect(await relaunched.items() == [item])
        let body = try Data(contentsOf: await relaunched.bodyFile(for: item.id))
        #expect(Int64(body.count) == item.bodyByteCount)
        let parts = MultipartParser.parts(of: body, boundary: item.boundary)
        #expect(parts.count == 3)
        let metadata = try #require(JSONSerialization.jsonObject(with: parts[0].body) as? [String: Any])
        #expect(metadata["client_id"] as? String == item.id.uuidString.lowercased())
    }

    @Test func itemsAreOldestFirst() async throws {
        let store = UploadQueueStore(directory: directory)
        let first = try await store.enqueue(pages: pages(1), workspaceID: workspaceID, deviceID: deviceID)
        let second = try await store.enqueue(pages: pages(1), workspaceID: workspaceID, deviceID: deviceID)

        #expect(await store.items().map(\.id) == [first.id, second.id])
    }

    @Test func updateIsPersisted() async throws {
        let store = UploadQueueStore(directory: directory)
        var item = try await store.enqueue(pages: pages(1), workspaceID: workspaceID, deviceID: deviceID)
        item.state = .failed
        item.failureCode = "document_conflict"
        item.attempt = 3

        try await store.update(item)

        #expect(await UploadQueueStore(directory: directory).items() == [item])
    }

    @Test func removeDeletesTheWholeItem() async throws {
        let store = UploadQueueStore(directory: directory)
        let item = try await store.enqueue(pages: pages(1), workspaceID: workspaceID, deviceID: deviceID)

        try await store.remove(item.id)

        #expect(await store.items().isEmpty)
        #expect(entries().isEmpty)
    }

    @Test func leftoversOfAnInterruptedEnqueueAreCleanedUp() async throws {
        let leftover = directory.appending(path: ".incoming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try Data("half".utf8).write(to: leftover.appending(path: "body.multipart"))

        let store = UploadQueueStore(directory: directory)

        #expect(await store.items().isEmpty)
        #expect(entries().isEmpty)
    }

    @Test func tooManyPagesAreRefusedBeforeAnythingIsWritten() async throws {
        // Review Focus 4
        let store = UploadQueueStore(directory: directory)

        await #expect(throws: UploadQueueError.tooManyPages) {
            try await store.enqueue(pages: pages(31), workspaceID: workspaceID, deviceID: deviceID)
        }
        await #expect(throws: UploadQueueError.noPages) {
            try await store.enqueue(pages: [], workspaceID: workspaceID, deviceID: deviceID)
        }
        #expect(entries().isEmpty)
    }

    @Test func tooLargeScanIsRefusedBeforeAnythingIsWritten() async throws {
        let limits = UploadLimits(maxPages: 30, maxBodyBytes: 1000, maxTextCharacters: 20_000)
        let store = UploadQueueStore(directory: directory, limits: limits)
        let big = [ScannedPage(jpeg: Data(repeating: 7, count: 2000), text: "")]

        await #expect(throws: UploadQueueError.tooLarge) {
            try await store.enqueue(pages: big, workspaceID: workspaceID, deviceID: deviceID)
        }
        #expect(entries().isEmpty)
    }

    @Test func fullDiskLeavesNothingBehind() async throws {
        let store = UploadQueueStore(directory: directory) { _, _, _, _, file in
            try Data("half".utf8).write(to: file)
            throw CocoaError(.fileWriteOutOfSpace)
        }

        await #expect(throws: UploadQueueError.diskFull) {
            try await store.enqueue(pages: pages(1), workspaceID: workspaceID, deviceID: deviceID)
        }
        #expect(entries().isEmpty)
        #expect(await store.items().isEmpty)
    }

    @Test func otherWriteFailureIsReported() async throws {
        let store = UploadQueueStore(directory: directory) { _, _, _, _, _ in
            throw CocoaError(.fileWriteNoPermission)
        }

        await #expect(throws: UploadQueueError.writeFailed) {
            try await store.enqueue(pages: pages(1), workspaceID: workspaceID, deviceID: deviceID)
        }
        #expect(entries().isEmpty)
    }

    @Test func queueIsExcludedFromBackup() async throws {
        let store = UploadQueueStore(directory: directory)
        let item = try await store.enqueue(pages: pages(1), workspaceID: workspaceID, deviceID: deviceID)

        let body = await store.bodyFile(for: item.id)
        for url in [directory, body.deletingLastPathComponent(), body] {
            let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
            #expect(values.isExcludedFromBackup == true)
        }
    }

    @Test func unreadableItemIsSkippedNotFatal() async throws {
        let store = UploadQueueStore(directory: directory)
        let item = try await store.enqueue(pages: pages(1), workspaceID: workspaceID, deviceID: deviceID)
        let broken = directory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("geen json".utf8).write(to: broken.appending(path: "item.json"))

        #expect(await store.items() == [item])
    }
}
