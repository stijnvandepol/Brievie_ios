import BrievieCore
import Foundation
import Observation

/// The post of one workspace: scans still on the phone and documents on the server, with where each one is
/// on its way from scan to confirmed.
@MainActor
@Observable
public final class DocumentsModel {
    public enum RowStatus: Equatable, Sendable {
        case waitingForUpload
        case uploading(progress: Double)
        case uploadFailed(message: String)
        case processing
        case needsReview
        case done
        case failed

        /// Something will change by itself: keep refreshing.
        var isMoving: Bool {
            switch self {
            case .waitingForUpload, .uploading, .processing: true
            case .uploadFailed, .needsReview, .done, .failed: false
            }
        }
    }

    public struct Row: Equatable, Identifiable, Sendable {
        /// The server's id, or the queue item's id while the scan is still on the phone.
        public let id: UUID
        /// `nil` while the scan has not reached the server: there is nothing to open yet.
        public let documentID: UUID?
        public let title: String
        public let subtitle: String
        public let status: RowStatus
    }

    public enum State: Equatable, Sendable {
        case loading
        case loaded
        case failed(message: String)
    }

    public private(set) var state: State = .loading
    public private(set) var rows: [Row] = []
    /// Members and admins may scan; a viewer only reads.
    public let canScan: Bool

    private let documents: WorkspaceDocuments
    private let uploads: any UploadQueue
    private let onRevoked: @MainActor () -> Void
    private let onMissingPairing: @MainActor () -> Void
    private let refreshInterval: Duration

    private var serverDocuments: [DocumentSummary] = []
    private var queued: [UploadItem] = []
    private var progress: [UUID: Double] = [:]
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    public init(
        documents: WorkspaceDocuments,
        uploads: any UploadQueue,
        canScan: Bool,
        onRevoked: @escaping @MainActor () -> Void,
        onMissingPairing: @escaping @MainActor () -> Void,
        refreshInterval: Duration = .seconds(3)
    ) {
        self.documents = documents
        self.uploads = uploads
        self.canScan = canScan
        self.onRevoked = onRevoked
        self.onMissingPairing = onMissingPairing
        self.refreshInterval = refreshInterval
    }

    public var workspaceID: UUID { documents.workspaceID }

    /// Something on screen is still on its way (uploading, being processed).
    public var needsRefresh: Bool { rows.contains { $0.status.isMoving } }

    /// Reads the queue and the server. A list that is already on screen stays when the server cannot be reached.
    public func load() async {
        queued = await uploads.items().filter { $0.workspaceID == documents.workspaceID }
        rebuild()
        do {
            serverDocuments = try await documents.list()
            // The queue may have moved on while the server answered.
            queued = await uploads.items().filter { $0.workspaceID == documents.workspaceID }
            state = .loaded
        } catch {
            switch error {
            case .revoked:
                onRevoked()
            case .missingPairing:
                onMissingPairing()
            case .cancelled:
                break
            default:
                if state != .loaded { state = .failed(message: Self.message(for: error)) }
            }
        }
        rebuild()
    }

    public func refreshIfNeeded() async {
        guard needsRefresh else { return }
        await load()
    }

    /// While the screen is visible: follow upload progress and refresh as long as something is moving.
    public func startPolling() {
        stopPolling()
        progressTask = Task { await observeProgress() }
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: refreshInterval)
                if Task.isCancelled { return }
                await refreshIfNeeded()
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        progressTask?.cancel()
        pollTask = nil
        progressTask = nil
    }

    func observeProgress() async {
        for await update in await uploads.progressUpdates() {
            progress = update
            rebuild()
        }
    }

    public func retryUpload(_ id: UUID) async {
        await uploads.retry(id)
        await load()
    }

    public func deleteUpload(_ id: UUID) async {
        await uploads.delete(id)
        await load()
    }

    private func rebuild() {
        let arrived = Set(serverDocuments.map(\.clientID))
        let waiting = queued
            .filter { !arrived.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
            .map { item in
                Row(
                    id: item.id, documentID: nil, title: DocumentStrings.newDocument,
                    subtitle: Self.subtitle(date: item.createdAt, pages: item.pageCount),
                    status: status(of: item)
                )
            }
        let onServer = serverDocuments
            .sorted { $0.createdAt > $1.createdAt }
            .map { document in
                Row(
                    id: document.id, documentID: document.id,
                    title: document.sender.isEmpty ? DocumentStrings.newDocument : document.sender,
                    subtitle: Self.subtitle(date: document.createdAt, pages: document.pageCount),
                    status: Self.status(of: document)
                )
            }
        rows = waiting + onServer
    }

    private func status(of item: UploadItem) -> RowStatus {
        switch item.state {
        case .waiting: .waitingForUpload
        case .uploading: .uploading(progress: progress[item.id] ?? 0)
        case .failed: .uploadFailed(message: Self.uploadMessage(for: item.failureCode))
        }
    }

    private static func status(of document: DocumentSummary) -> RowStatus {
        switch document.status {
        case .processing: .processing
        case .needsReview: .needsReview
        case .failed: .failed
        // A status this app does not know yet is at least a document that can be opened.
        case .done, .unknown: .done
        }
    }

    private static func uploadMessage(for code: String?) -> String {
        switch code {
        case "untrusted": DocumentStrings.notVerified
        case "workspace_not_found": DocumentStrings.workspaceGone
        case "payload_too_large": DocumentStrings.tooLarge
        default: DocumentStrings.uploadFailed
        }
    }

    static func message(for error: DocumentsError) -> String {
        switch error {
        case .unreachable: DocumentStrings.unreachable
        case .notVerified: DocumentStrings.notVerified
        case .notFound: DocumentStrings.notFound
        default: DocumentStrings.generic
        }
    }

    private static let dateStyle = Date.FormatStyle(
        date: .abbreviated, time: .omitted, locale: Locale(identifier: "nl_NL")
    )

    static func subtitle(date: Date, pages: Int) -> String {
        let pageText = pages == 1 ? DocumentStrings.pagesOne : String(format: DocumentStrings.pagesManyFormat, pages)
        return "\(date.formatted(dateStyle)) · \(pageText)"
    }
}
