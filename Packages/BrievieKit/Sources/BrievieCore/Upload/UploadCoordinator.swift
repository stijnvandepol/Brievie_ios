import BrievieScan
import Foundation

/// Runs the upload queue: starts what waits, decides what happens after each attempt (`UploadPolicy`),
/// and keeps the queue on disk in step. One per process.
public actor UploadCoordinator {
    public typealias Connection = @Sendable () throws -> (ServerConnection, String)?

    /// Device id stored on an item that was queued while unpaired; replaced at its first attempt.
    private static let noDevice = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    private let store: UploadQueueStore
    private let transport: any UploadTransport
    private let connection: Connection
    private let onRevoked: @Sendable (UUID) async -> Void
    private let now: @Sendable () -> Date

    /// Items being started right now: an actor is re-entered at every `await`, and an item must not start twice.
    private var starting: Set<UUID> = []
    /// The pairing the server refused; nothing is sent with it again.
    private var revokedDevice: UUID?
    private var progress: [UUID: Double] = [:]
    private var subscribers: [UUID: AsyncStream<[UUID: Double]>.Continuation] = [:]
    private var eventsHandler: (@MainActor @Sendable () -> Void)?
    /// The system's events were all handled before the app delegate handed over its completion handler.
    private var eventsDeliveredEarly = false

    public init(
        store: UploadQueueStore,
        transport: any UploadTransport,
        connection: @escaping Connection,
        onRevoked: @escaping @Sendable (_ deviceID: UUID) async -> Void,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.transport = transport
        self.connection = connection
        self.onRevoked = onRevoked
        self.now = now
    }

    /// Handles the transport's events until its stream ends. Started once at launch.
    public func run() async {
        for await event in transport.events {
            await handle(event)
        }
    }

    /// Writes the scan to the queue and starts its upload. The scan is safe on disk when this returns.
    public func enqueue(pages: [ScannedPage], workspaceID: UUID) async throws(UploadQueueError) -> UploadItem {
        let paired = current()
        let deviceID = paired?.connection.deviceID ?? Self.noDevice
        var item = try await store.enqueue(pages: pages, workspaceID: workspaceID, deviceID: deviceID)
        if let serverID = paired?.connection.serverID {
            item.serverID = serverID
            try? await store.update(item)
        }
        await start(item)
        return await store.item(item.id) ?? item
    }

    /// Starts every waiting item, and every item that was uploading when the app was killed.
    public func resume() async {
        let running = await transport.runningItemIDs()
        for item in await store.items() {
            switch item.state {
            case .waiting:
                await start(item)
            case .uploading where !running.contains(item.id):
                await start(item)
            case .uploading, .failed:
                break
            }
        }
    }

    /// For the user's "try again" on a failed item.
    public func retry(_ id: UUID) async {
        guard var item = await store.item(id), item.state == .failed else { return }
        item.state = .waiting
        item.attempt = 0
        item.urlIndex = 0
        item.nextAttemptAt = nil
        item.failureCode = nil
        try? await store.update(item)
        await start(item)
    }

    public func delete(_ id: UUID) async {
        await transport.cancel(itemID: id)
        try? await store.remove(id)
        setProgress(nil, for: id)
    }

    public func removeAll() async throws {
        let ids = Set(await store.items().map(\.id)).union(await transport.runningItemIDs())
        for id in ids {
            await transport.cancel(itemID: id)
        }
        // A late event of a cancelled upload finds no item and changes nothing.
        try await store.removeAll()
        for id in progress.keys {
            setProgress(nil, for: id)
        }
    }

    public func items() async -> [UploadItem] {
        await store.items()
    }

    /// Upload progress (0...1) per running item. Every caller gets its own stream.
    public func progressUpdates() -> AsyncStream<[UUID: Double]> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: [UUID: Double].self, bufferingPolicy: .bufferingNewest(1)
        )
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        if !progress.isEmpty { continuation.yield(progress) }
        return stream
    }

    /// The completion handler iOS hands the app when it relaunches it for finished uploads.
    public func setEventsHandler(_ handler: @escaping @MainActor @Sendable () -> Void) async {
        if eventsDeliveredEarly {
            eventsDeliveredEarly = false
            await MainActor.run { handler() }
        } else {
            eventsHandler = handler
        }
    }

    // MARK: - Events

    func handle(_ event: UploadEvent) async {
        switch event {
        case let .sent(itemID, bytes, total):
            setProgress(total > 0 ? Double(bytes) / Double(total) : 0, for: itemID)
        case let .finished(itemID, deviceID, attemptID, outcome):
            await finished(itemID: itemID, deviceID: deviceID, attemptID: attemptID, outcome: outcome)
        case .allEventsDelivered:
            // Only now: the queue on disk reflects every event the system delivered.
            if let handler = eventsHandler {
                eventsHandler = nil
                await MainActor.run { handler() }
            } else {
                eventsDeliveredEarly = true
            }
        }
    }

    private func finished(itemID: UUID, deviceID: UUID, attemptID: UUID, outcome: UploadOutcome) async {
        // Gone (deleted), not uploading any more (set back to waiting after a revocation), or an event of an
        // earlier attempt (a task the system cancelled after the item was started again): nothing to decide.
        guard outcome != .cancelledByUser, var item = await store.item(itemID), item.state == .uploading,
              item.attemptID == attemptID
        else { return }
        setProgress(nil, for: itemID)
        let urlCount = max(current()?.connection.urls.count ?? 1, 1)
        switch UploadPolicy.decide(outcome, item: item, urlCount: urlCount) {
        case .done:
            try? await store.remove(itemID)
        case let .retry(urlIndex, after):
            item.state = .waiting
            item.urlIndex = urlIndex
            if after > .zero {
                item.attempt += 1
                let seconds = Double(after.components.seconds)
                item.nextAttemptAt = UploadQueueStore.wholeMilliseconds(now().addingTimeInterval(seconds))
            } else {
                item.nextAttemptAt = nil
            }
            try? await store.update(item)
            await start(item)
        case let .failed(code):
            item.state = .failed
            item.failureCode = code
            try? await store.update(item)
        case .revoked:
            await revoked(item, deviceID: deviceID)
        case .paused:
            // Waits for `resume()` after the next pairing; not a failed attempt.
            item.state = .waiting
            try? await store.update(item)
        }
    }

    /// The server refused the token of `deviceID`. Nothing is deleted: the scans go out after pairing again.
    private func revoked(_ item: UploadItem, deviceID: UUID) async {
        var item = item
        item.state = .waiting
        try? await store.update(item)
        await onRevoked(deviceID)

        if let paired = current(), paired.connection.deviceID != deviceID {
            // A late answer to an older pairing; the current one is fine.
            await start(item)
            return
        }
        revokedDevice = deviceID
        for other in await store.items() where other.state == .uploading {
            await transport.cancel(itemID: other.id)
            var other = other
            other.state = .waiting
            try? await store.update(other)
        }
    }

    // MARK: - Starting

    private func start(_ item: UploadItem) async {
        guard !starting.contains(item.id) else { return }
        guard let paired = current(), paired.connection.deviceID != revokedDevice,
              !paired.connection.urls.isEmpty
        else { return }
        starting.insert(item.id)
        defer { starting.remove(item.id) }

        // Re-read: another call may have started it while this one waited for the actor.
        guard var fresh = await store.item(item.id) else { return }
        // Only `retry` restarts a failed item (it sets it to waiting first), except that a scan made for
        // another server stays failed whatever is tried.
        if fresh.state == .failed { return }
        if fresh.state == .uploading, await transport.runningItemIDs().contains(fresh.id) { return }

        // A scan belongs to the server it was made for: after pairing with another server it stays here.
        let serverID = paired.connection.serverID
        if let madeFor = fresh.serverID, madeFor != serverID {
            fresh.state = .failed
            fresh.failureCode = "server_changed"
            try? await store.update(fresh)
            return
        }

        let urls = paired.connection.urls
        let attemptID = UUID()
        fresh.urlIndex = min(fresh.urlIndex, urls.count - 1)
        fresh.state = .uploading
        fresh.deviceID = paired.connection.deviceID
        fresh.serverID = serverID
        fresh.attemptID = attemptID
        // Saved before the transfer starts, so a relaunch knows this item was on its way.
        guard (try? await store.update(fresh)) != nil else { return }

        let earliest = fresh.nextAttemptAt.flatMap { $0 > now() ? $0 : nil }
        await transport.start(UploadRequest(
            itemID: fresh.id,
            deviceID: paired.connection.deviceID,
            attemptID: attemptID,
            url: BackgroundUploadTransport.uploadURL(base: urls[fresh.urlIndex], workspaceID: fresh.workspaceID),
            bodyFile: await store.bodyFile(for: fresh.id),
            boundary: fresh.boundary,
            token: paired.token,
            earliestBegin: earliest
        ))
    }

    private func current() -> (connection: ServerConnection, token: String)? {
        guard let paired = try? connection() else { return nil }
        return (paired.0, paired.1)
    }

    private func setProgress(_ value: Double?, for id: UUID) {
        guard progress[id] != value else { return }
        progress[id] = value
        for subscriber in subscribers.values {
            subscriber.yield(progress)
        }
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }
}
