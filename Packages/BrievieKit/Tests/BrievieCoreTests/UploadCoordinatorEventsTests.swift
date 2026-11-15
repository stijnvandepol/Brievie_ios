@testable import BrievieCore
import Foundation
import Testing

/// The completion handler iOS hands over when it relaunches the app for finished uploads.
@Suite struct UploadCoordinatorEventsTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "queue-\(UUID().uuidString)")

    private func coordinator() -> UploadCoordinator {
        UploadCoordinator(
            store: UploadQueueStore(directory: directory),
            transport: FakeUploadTransport(),
            connection: { nil },
            onRevoked: { _ in }
        )
    }

    @Test func everyHandlerHandedOverBeforeTheEventsRunsOnce() async throws {
        // The system can wake the app twice before the events are in; neither handler may be lost.
        let uploads = coordinator()
        let calls = Locked<[String]>([])

        await uploads.setEventsHandler { calls.value.append("first") }
        await uploads.setEventsHandler { calls.value.append("second") }
        await uploads.handle(.allEventsDelivered)
        await uploads.handle(.allEventsDelivered)

        #expect(calls.value == ["first", "second"])
    }

    @Test func earlyDeliveryIsUsedOnceOnly() async throws {
        let uploads = coordinator()
        let calls = Locked(0)

        await uploads.handle(.allEventsDelivered)
        await uploads.setEventsHandler { calls.value += 1 }
        // A later wake-up waits for its own events.
        await uploads.setEventsHandler { calls.value += 10 }
        #expect(calls.value == 1)

        await uploads.handle(.allEventsDelivered)
        #expect(calls.value == 11)
    }

    @Test func handlerRunsOnTheMainActor() async throws {
        let uploads = coordinator()
        let onMain = Locked(false)

        await uploads.setEventsHandler { onMain.value = Thread.isMainThread }
        await uploads.handle(.allEventsDelivered)

        #expect(onMain.value)
    }
}
