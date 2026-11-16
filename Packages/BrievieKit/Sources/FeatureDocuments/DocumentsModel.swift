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
        /// `canRetry` is false for a scan that belongs to another server: it can only be deleted.
        case uploadFailed(message: String, canRetry: Bool = true)
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

    public enum State: Equatable, Sendable {
        case loading
        case loaded
        case failed(message: String)
    }

    /// Why the scanner did not open.
    public enum CameraNotice: Equatable, Sendable {
        /// Access refused: Settings can change it.
        case denied
        /// The device forbids the camera.
        case restricted
    }

    public private(set) var state: State = .loading
    public private(set) var scope: Scope = .inbox
    /// The rows of the current scope, grouped. `rows` is the same rows in one list.
    public private(set) var groups: [RowGroup] = []
    public private(set) var rows: [Row] = []
    /// The persons and labels of the workspace, to name a row's addressees and labels. Empty against a
    /// server without them (phase 1b answers 404); that does not fail the screen.
    public private(set) var persons: [Person] = []
    public private(set) var labels: [DocumentLabel] = []
    /// Members and admins may scan; a viewer only reads.
    public let canScan: Bool
    /// Shown after "Scan een brief" when the camera may not be used; photos remain the way in.
    public private(set) var cameraNotice: CameraNotice?
    /// Scans the queue removed because they could not be read; shown while this screen is open.
    public private(set) var removedNotice: String?

    private let documents: WorkspaceDocuments
    private let uploads: any UploadQueue
    private let camera: any ScanCameraAccess
    private let settingsOpener: @MainActor () -> Void
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
        camera: any ScanCameraAccess,
        openSettings: @escaping @MainActor () -> Void,
        onRevoked: @escaping @MainActor () -> Void,
        onMissingPairing: @escaping @MainActor () -> Void,
        refreshInterval: Duration = .seconds(3)
    ) {
        self.documents = documents
        self.uploads = uploads
        self.canScan = canScan
        self.camera = camera
        settingsOpener = openSettings
        self.onRevoked = onRevoked
        self.onMissingPairing = onMissingPairing
        self.refreshInterval = refreshInterval
    }

    public var workspaceID: UUID { documents.workspaceID }

    /// Something on screen is still on its way (uploading, being processed).
    public var needsRefresh: Bool { rows.contains { $0.status.isMoving } }

    /// Reads the queue and the server. A list that is already on screen stays when the server cannot be reached.
    public func load() async {
        let removed = await uploads.takeRemovedUnreadableCount()
        if removed > 0 { removedNotice = DocumentStrings.unreadableRemoved(removed) }
        queued = await uploads.items().filter { $0.workspaceID == documents.workspaceID }
        rebuild()
        let filter = Self.filter(for: scope)
        async let fetchedPersons = try? documents.persons()
        async let fetchedLabels = try? documents.labels()
        do {
            let listed = try await documents.list(filter: filter)
            // Another scope was chosen while the server answered: its own load shows it.
            guard filter == Self.filter(for: scope) else { return }
            serverDocuments = listed
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
        if let fetched = await fetchedPersons { persons = fetched }
        if let fetched = await fetchedLabels { labels = fetched }
        rebuild()
    }

    /// Shows another scope. A scope with another server list starts empty, so no wrong post shows meanwhile.
    public func select(_ scope: Scope) async {
        guard scope != self.scope else { return }
        if Self.filter(for: scope) != Self.filter(for: self.scope) {
            serverDocuments = []
            state = .loading
        }
        self.scope = scope
        rebuild()
        await load()
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

    /// Before the scanner opens: asks for the camera the first time; `false` (with a notice) when it may not
    /// be used.
    public func prepareScanner() async -> Bool {
        var status = camera.status()
        if status == .notDetermined {
            status = await camera.requestAccess() ? .allowed : .denied
        }
        switch status {
        case .allowed:
            cameraNotice = nil
            return true
        case .restricted:
            cameraNotice = .restricted
        case .denied, .notDetermined:
            cameraNotice = .denied
        }
        return false
    }

    /// When the app is active again: access granted in Settings hides the notice. Never asks.
    public func refreshCameraNotice() {
        if cameraNotice != nil, camera.status() == .allowed { cameraNotice = nil }
    }

    public func openSettings() {
        settingsOpener()
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
        // A scan on the phone has no addressee yet: it is not under a person.
        let waiting = scope.showsQueue ? waitingRows(arrived: arrived) : []
        let onServer = serverDocuments
            .sorted { $0.createdAt > $1.createdAt }
            .map { document in (document.inboxState, row(for: document)) }
        groups = makeGroups(waiting: waiting, onServer: onServer)
        rows = groups.flatMap(\.rows)
    }

    private func waitingRows(arrived: Set<UUID>) -> [Row] {
        queued
            .filter { !arrived.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
            .map { item in
                Row(
                    id: item.id, documentID: nil, title: DocumentStrings.newDocument,
                    subtitle: Self.subtitle(date: item.createdAt, pages: item.pageCount),
                    status: status(of: item)
                )
            }
    }

    private func row(for document: DocumentSummary) -> Row {
        let addressees = Set(document.addresseeIDs)
        let labelIDs = Set(document.labelIDs)
        return Row(
            id: document.id, documentID: document.id,
            title: document.sender.isEmpty ? DocumentStrings.newDocument : document.sender,
            subtitle: Self.subtitle(date: document.createdAt, pages: document.pageCount),
            status: Self.status(of: document),
            addressees: persons.filter { addressees.contains($0.id) }.map(\.displayName),
            labels: labels.filter { labelIDs.contains($0.id) },
            hasSuggestions: document.openSuggestionCount > 0
        )
    }

    private func status(of item: UploadItem) -> RowStatus {
        switch item.state {
        case .waiting: .waitingForUpload
        case .uploading:
            // Handed to the system but nothing sent yet (offline, or scheduled for later): it waits.
            progress[item.id].map { .uploading(progress: $0) } ?? .waitingForUpload
        case .failed:
            .uploadFailed(
                message: Self.uploadMessage(for: item.failureCode), canRetry: item.failureCode != "server_changed"
            )
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
        case "server_changed": DocumentStrings.otherServer
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
