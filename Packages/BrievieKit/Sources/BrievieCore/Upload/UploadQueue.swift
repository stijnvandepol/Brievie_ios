import BrievieScan
import Foundation

/// What a screen needs from the upload queue. `UploadCoordinator` is the live one.
public protocol UploadQueue: Sendable {
    func enqueue(pages: [ScannedPage], workspaceID: UUID) async throws(UploadQueueError) -> UploadItem
    func items() async -> [UploadItem]
    func retry(_ id: UUID) async
    func delete(_ id: UUID) async
    /// Unpairing: stops every upload and deletes every queued scan with its files. Throws when something
    /// could not be deleted; calling it again finishes the job.
    func removeAll() async throws
    /// Upload progress (0...1) per running item; every caller gets its own stream.
    func progressUpdates() async -> AsyncStream<[UUID: Double]>
}

extension UploadCoordinator: UploadQueue {}
