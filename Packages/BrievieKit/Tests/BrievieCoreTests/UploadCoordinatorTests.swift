@testable import BrievieCore
import BrievieScan
import Foundation
import Testing

@Suite struct UploadCoordinatorTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let local = URL(string: "https://brievie.local")!
    private static let remote = URL(string: "https://brievie.example.nl")!

    private let directory = FileManager.default.temporaryDirectory.appending(path: "queue-\(UUID().uuidString)")
    private let transport = FakeUploadTransport()
    private let workspaceID = UUID()
    private let pairing = Locked<(ServerConnection, String)?>(nil)
    private let revoked = Locked<[UUID]>([])
    private let deviceA = UUID()

    init() {
        pair(deviceID: deviceA, urls: [Self.local])
    }

    private func pair(deviceID: UUID, urls: [URL], token: String = "token-a") {
        let connection = ServerConnection(urls: urls, caCertificateDER: nil, deviceID: deviceID, userName: "Stijn")
        pairing.value = (connection, token)
    }

    private func coordinator() -> UploadCoordinator {
        UploadCoordinator(
            store: UploadQueueStore(directory: directory),
            transport: transport,
            connection: { [pairing] in pairing.value },
            onRevoked: { [revoked] id in revoked.update { $0.append(id) } },
            now: { Self.now }
        )
    }

    private func endpoint(_ base: URL) -> URL {
        base.appending(path: "api/v1/workspaces/\(workspaceID.uuidString.lowercased())/documents")
    }

    private var page: [ScannedPage] { [ScannedPage(jpeg: Data([0xFF, 0xD8, 0xFF, 1]), text: "tekst")] }

    /// The end of the item's latest attempt, as the transport would report it.
    private func finished(_ item: UploadItem, _ outcome: UploadOutcome, device: UUID? = nil) -> UploadEvent {
        let attempt = transport.starts.last { $0.itemID == item.id }?.attemptID ?? UUID()
        return .finished(itemID: item.id, deviceID: device ?? deviceA, attemptID: attempt, outcome: outcome)
    }

    private func entries() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []).sorted()
    }

    @Test func scanWithoutConnectionIsUploadedLater() async throws {
        // Spec acceptance: "Een scan zonder verbinding wordt later vanzelf geüpload" (Review Focus 1).
        let uploads = coordinator()

        let item = try await uploads.enqueue(pages: page, workspaceID: workspaceID)
        #expect(transport.starts == [
            .init(
                itemID: item.id, deviceID: deviceA, url: endpoint(Self.local), token: "token-a", earliestBegin: nil
            )
        ])
        #expect(await uploads.items().map(\.state) == [.uploading])

        await uploads.handle(finished(item, .unreachable))

        #expect(transport.starts.count == 2)
        #expect(transport.starts[1].earliestBegin == Self.now.addingTimeInterval(30))
        let waiting = try #require(await uploads.items().first)
        #expect(waiting.attempt == 1)
        #expect(waiting.nextAttemptAt == Self.now.addingTimeInterval(30))

        await uploads.handle(finished(item, .status(201, code: nil)))

        #expect(await uploads.items().isEmpty)
        #expect(entries().isEmpty)
    }

    @Test func unreachableFirstURLTriesTheSecondAtOnce() async throws {
        pair(deviceID: deviceA, urls: [Self.local, Self.remote])
        let uploads = coordinator()
        let item = try await uploads.enqueue(pages: page, workspaceID: workspaceID)

        await uploads.handle(finished(item, .unreachable))

        #expect(transport.starts.map(\.url) == [endpoint(Self.local), endpoint(Self.remote)])
        #expect(transport.starts[1].earliestBegin == nil)
        #expect(await uploads.items().first?.attempt == 0)
    }

    @Test func relaunchStartsWaitingItemsButNotRunningOnes() async throws {
        let first = coordinator()
        let running = try await first.enqueue(pages: page, workspaceID: workspaceID)
        let lost = try await first.enqueue(pages: page, workspaceID: workspaceID)
        // After a relaunch the system still runs one upload; the other one is gone (killed mid-upload).
        transport.setRunning([running.id])
        let relaunched = coordinator()

        await relaunched.resume()

        #expect(transport.starts.map(\.itemID) == [running.id, lost.id, lost.id])
    }

    @Test func itemIsStartedOnceWhenEnqueueAndResumeOverlap() async throws {
        let uploads = coordinator()

        async let enqueued = uploads.enqueue(pages: page, workspaceID: workspaceID)
        async let resumed: Void = uploads.resume()
        let item = try await enqueued
        await resumed
        await uploads.resume()

        #expect(transport.starts.map(\.itemID) == [item.id])
    }

    @Test func revokedDeviceKeepsTheQueueForAfterPairingAgain() async throws {
        // Review Focus 3
        let uploads = coordinator()
        let first = try await uploads.enqueue(pages: page, workspaceID: workspaceID)
        let second = try await uploads.enqueue(pages: page, workspaceID: workspaceID)

        await uploads.handle(finished(first, .status(401, code: "not_authenticated")))

        #expect(revoked.value == [deviceA])
        #expect(transport.cancelled == [second.id])
        #expect(await uploads.items().map(\.state) == [.waiting, .waiting])
        #expect(entries().count == 2)
        // The cancelled upload reports back; it must not count as a failure or start again.
        await uploads.handle(finished(second, .unreachable))
        await uploads.resume()
        #expect(transport.starts.count == 2)

        let deviceB = UUID()
        pair(deviceID: deviceB, urls: [Self.local], token: "token-b")
        await uploads.resume()

        #expect(transport.starts.suffix(2).map(\.deviceID) == [deviceB, deviceB])
        #expect(transport.starts.suffix(2).map(\.token) == ["token-b", "token-b"])
        #expect(await uploads.items().map(\.deviceID) == [deviceB, deviceB])
    }

    @Test func lateAnswerForAnOldPairingDoesNotStopTheNewOne() async throws {
        let uploads = coordinator()
        let item = try await uploads.enqueue(pages: page, workspaceID: workspaceID)
        let deviceB = UUID()
        pair(deviceID: deviceB, urls: [Self.local], token: "token-b")

        await uploads.handle(finished(item, .status(401, code: "not_authenticated"), device: deviceA))

        // The old device is reported (AppModel ignores a stale id); the item goes out with the new pairing.
        #expect(revoked.value == [deviceA])
        #expect(transport.starts.last?.deviceID == deviceB)
        #expect(await uploads.items().map(\.state) == [.uploading])
    }

    @Test func conflictFailsAndCanBeRetried() async throws {
        let uploads = coordinator()
        let item = try await uploads.enqueue(pages: page, workspaceID: workspaceID)

        await uploads.handle(finished(item, .status(409, code: "document_conflict")))

        let failed = try #require(await uploads.items().first)
        #expect(failed.state == .failed)
        #expect(failed.failureCode == "document_conflict")
        await uploads.resume()
        #expect(transport.starts.count == 1)

        await uploads.retry(item.id)

        let retried = try #require(await uploads.items().first)
        #expect(retried.state == .uploading)
        #expect(retried.attempt == 0)
        #expect(retried.failureCode == nil)
        #expect(transport.starts.count == 2)
    }

    @Test func deleteCancelsAndRemovesTheFiles() async throws {
        let uploads = coordinator()
        let item = try await uploads.enqueue(pages: page, workspaceID: workspaceID)

        await uploads.delete(item.id)
        await uploads.handle(finished(item, .cancelledByUser))

        #expect(transport.cancelled == [item.id])
        #expect(await uploads.items().isEmpty)
        #expect(entries().isEmpty)
        #expect(transport.starts.count == 1)
    }

    @Test func everySubscriberSeesProgress() async throws {
        let uploads = coordinator()
        let item = try await uploads.enqueue(pages: page, workspaceID: workspaceID)
        var first = await uploads.progressUpdates().makeAsyncIterator()
        var second = await uploads.progressUpdates().makeAsyncIterator()

        await uploads.handle(.sent(itemID: item.id, bytes: 50, total: 100))

        #expect(await first.next() == [item.id: 0.5])
        #expect(await second.next() == [item.id: 0.5])
    }

    @Test func eventsSentBeforeRunStartsAreStillHandled() async throws {
        let uploads = coordinator()
        let item = try await uploads.enqueue(pages: page, workspaceID: workspaceID)
        transport.send(finished(item, .status(200, code: nil)))
        transport.finish()

        await uploads.run()

        #expect(await uploads.items().isEmpty)
    }

    @Test func eventsHandlerRunsAfterTheQueueIsUpdated() async throws {
        let uploads = coordinator()
        let item = try await uploads.enqueue(pages: page, workspaceID: workspaceID)
        let itemsWhenCalled = Locked<Int?>(nil)
        let directory = directory
        await uploads.setEventsHandler {
            let path = directory.path(percentEncoded: false)
            let left = (try? FileManager.default.contentsOfDirectory(atPath: path))?.count
            itemsWhenCalled.value = left
        }

        await uploads.handle(finished(item, .status(201, code: nil)))
        await uploads.handle(.allEventsDelivered)

        #expect(itemsWhenCalled.value == 0)
    }

    @Test func nothingStartsWhileUnpaired() async throws {
        pairing.value = nil
        let uploads = coordinator()

        let item = try await uploads.enqueue(pages: page, workspaceID: workspaceID)

        #expect(transport.starts.isEmpty)
        #expect(await uploads.items().map(\.state) == [.waiting])
        pair(deviceID: deviceA, urls: [Self.local])
        await uploads.resume()
        #expect(transport.starts.map(\.itemID) == [item.id])
    }

    @Test func lateEventOfAnEarlierAttemptIsIgnored() async throws {
        // Final review: swiped away and reopened: the item is restarted, then the old task's cancel arrives.
        let uploads = coordinator()
        let item = try await uploads.enqueue(pages: page, workspaceID: workspaceID)
        let oldAttempt = try #require(transport.starts.first?.attemptID)
        transport.setRunning([])
        await uploads.resume()
        #expect(transport.starts.count == 2)

        await uploads.handle(
            .finished(itemID: item.id, deviceID: deviceA, attemptID: oldAttempt, outcome: .unreachable)
        )

        #expect(transport.starts.count == 2)
        let current = try #require(await uploads.items().first)
        #expect(current.state == .uploading)
        #expect(current.attempt == 0)
        await uploads.handle(finished(item, .status(201, code: nil)))
        #expect(await uploads.items().isEmpty)
    }

    @Test func scanQueuedForOneServerIsNeverSentToAnother() async throws {
        // Final review: revoked, then paired with a different server: the scans must stay here.
        let uploads = coordinator()
        let item = try await uploads.enqueue(pages: page, workspaceID: workspaceID)
        await uploads.handle(finished(item, .status(401, code: "not_authenticated")))
        let other = ServerConnection(
            urls: [Self.remote], caCertificateDER: Data([1, 2, 3]), deviceID: UUID(), userName: "Iemand"
        )
        pairing.value = (other, "token-other")

        await uploads.resume()

        #expect(transport.starts.count == 1)
        let kept = try #require(await uploads.items().first)
        #expect(kept.state == .failed)
        #expect(kept.failureCode == "server_changed")
        // Trying again does not help either; the user can only delete it.
        await uploads.retry(item.id)
        #expect(transport.starts.count == 1)
        #expect(await uploads.items().first?.failureCode == "server_changed")
    }

    @Test func uploadRefusedForLackOfAPairingWaitsForTheNextOne() async throws {
        // Final review: a 401 elsewhere cleared the pairing; a scheduled upload then finds no pin.
        let uploads = coordinator()
        let item = try await uploads.enqueue(pages: page, workspaceID: workspaceID)
        pairing.value = nil

        await uploads.handle(finished(item, .unpaired))

        let waiting = try #require(await uploads.items().first)
        #expect(waiting.state == .waiting)
        #expect(waiting.attempt == 0)
        #expect(waiting.failureCode == nil)
        #expect(transport.starts.count == 1)

        pair(deviceID: UUID(), urls: [Self.local], token: "token-b")
        await uploads.resume()
        #expect(transport.starts.count == 2)
    }

    @Test func eventsHandlerSetAfterTheEventsWereDeliveredRunsAtOnce() async throws {
        // Final review: the system's events can be handled before the app delegate hands over its handler.
        let uploads = coordinator()
        let called = Locked(false)

        await uploads.handle(.allEventsDelivered)
        await uploads.setEventsHandler { called.value = true }

        #expect(called.value)
    }
}
