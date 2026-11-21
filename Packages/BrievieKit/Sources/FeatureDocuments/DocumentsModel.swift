import BrievieCore
import Foundation
import Observation

/// The post of one workspace: scans still on the phone and documents on the server, with where each one is
/// on its way from scan to confirmed.
@MainActor
@Observable
public final class DocumentsModel {
    /// What a row needs, in the words of the web: "Controleren", "Naam kiezen", "Bezig…", "Klaar"; a scan still
    /// on the phone says where its upload stands.
    public enum RowStatus: Equatable, Sendable {
        case waitingForUpload
        case uploading(progress: Double)
        /// `canRetry` is false for a scan that belongs to another server: it can only be deleted.
        case uploadFailed(message: String, canRetry: Bool = true)
        /// "Bezig…": the server is reading the letter; nothing to do yet.
        case processing
        /// "Controleren".
        case needsReview
        /// "Controleren" too: the server could not read the letter, so the person fills it in.
        case failed
        /// "Naam kiezen": read, but on nobody's name.
        case needsName
        case done

        /// Something will change by itself: keep refreshing. The same rows close "Inbox".
        var isMoving: Bool { isUnderway }

        /// On its way, nothing for the person to do: an upload that is waiting or running, a letter being read.
        var isUnderway: Bool {
            switch self {
            case .waitingForUpload, .uploading, .processing: true
            case .uploadFailed, .needsReview, .failed, .needsName, .done: false
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
    /// The rows of the current scope, in one list (see `arrange(waiting:onServer:)` for the order).
    public private(set) var rows: [Row] = []
    /// The line above "Inbox": how many rows need what. `nil` in the other scopes and without rows.
    public private(set) var summary: String?
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
    /// A letter opened from outside the list (a tapped reminder): the screen pushes it.
    public var openedDocument: UUID?
    /// Search in "Alle post"; forgotten when the user leaves it (and with this model, on a workspace switch or when
    /// the session ends).
    public let search: DocumentSearchModel

    private let documents: WorkspaceDocuments
    private let uploads: any UploadQueue
    private let camera: any ScanCameraAccess
    private let settingsOpener: @MainActor () -> Void
    private let onRevoked: @MainActor () -> Void
    private let onMissingPairing: @MainActor () -> Void
    private let refreshInterval: Duration

    private var serverDocuments: [DocumentSummary] = []
    /// In the inbox: per state, the number its header names (more than shown when only the newest are listed).
    private var inboxTotals: [InboxState: Int] = [:]
    private var queued: [UploadItem] = []
    /// The number of the latest load: only that one writes the server's answer (a newer load always wins).
    @ObservationIgnored private var latestLoad = 0
    /// Full loads (not a tick) still waiting for the server. A tick is skipped meanwhile: the full load also
    /// asks for what the tick would, and a newer tick would make it lose.
    @ObservationIgnored private var wholeLoadsInFlight = 0
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
        refreshInterval: Duration = .seconds(3),
        searchDelay: Duration = DocumentSearchModel.typingPause
    ) {
        self.documents = documents
        self.uploads = uploads
        self.canScan = canScan
        self.camera = camera
        settingsOpener = openSettings
        self.onRevoked = onRevoked
        self.onMissingPairing = onMissingPairing
        self.refreshInterval = refreshInterval
        search = DocumentSearchModel(
            documents: documents, onRevoked: onRevoked, onMissingPairing: onMissingPairing, delay: searchDelay
        )
    }

    public var workspaceID: UUID { documents.workspaceID }

    /// Something on screen is still on its way (uploading, being processed).
    public var needsRefresh: Bool { rows.contains { $0.status.isMoving } }

    /// Reads the queue, the server's list and the workspace's persons and labels. A list that is already on
    /// screen stays when the server cannot be reached. For the first load, pull-to-refresh and retry.
    public func load() async {
        await load(organisation: true)
    }

    /// Shows another scope. A scope with another server list starts empty, so no wrong post shows meanwhile.
    public func select(_ scope: Scope) async {
        guard scope != self.scope else { return }
        if scope != .all { search.forget() }
        if Self.source(for: scope) != Self.source(for: self.scope) {
            serverDocuments = []
            inboxTotals = [:]
            state = .loading
        }
        self.scope = scope
        rebuild()
        await load()
    }

    /// The automatic refresh while something moves: one list, not the persons and labels. In a loaded "Inbox"
    /// only the letters on their way ("Bezig…"); the whole of it once when a letter left that list or a scan
    /// left the upload queue without showing up in it (read by the server within one tick), so it shows up with
    /// its new status. An inbox that is not loaded (still loading, or failed) is loaded whole.
    public func refreshIfNeeded() async {
        guard needsRefresh, wholeLoadsInFlight == 0 else { return }
        await load(organisation: false, movingOnly: state == .loaded)
    }

    /// Every write that belongs to one scope is checked against the scope after each wait: a slow answer
    /// for a scope the user has left never touches the current one, and only the latest load writes.
    private func load(organisation: Bool, movingOnly: Bool = false) async {
        let source = Self.source(for: scope)
        latestLoad += 1
        let load = latestLoad
        if !movingOnly { wholeLoadsInFlight += 1 }
        defer { if !movingOnly { wholeLoadsInFlight -= 1 } }
        let shownQueue = Set(queued.map(\.id))
        let removed = await uploads.takeRemovedUnreadableCount()
        if removed > 0 { removedNotice = DocumentStrings.unreadableRemoved(removed) }
        queued = await uploads.items().filter { $0.workspaceID == documents.workspaceID }
        // Also a scan that only joined the queue now: it may be read by the server before the answer comes.
        let wasQueued = shownQueue.union(queued.map(\.id))
        rebuild()
        async let fetchedPersons = Self.persons(of: documents, if: organisation)
        async let fetchedLabels = Self.labels(of: documents, if: organisation)
        do {
            try await loadServerList(source, movingOnly: movingOnly, load: load, wasQueued: wasQueued)
        } catch {
            if await handleFailure(error, source: source, load: load) { return }
        }
        // Persons and labels belong to the workspace, not to a scope.
        let freshPersons = await fetchedPersons
        if let freshPersons { persons = freshPersons }
        if let fetched = await fetchedLabels { labels = fetched }
        search.use(persons: persons, labels: labels)
        // The chosen person was archived or removed meanwhile: back to the inbox.
        if let freshPersons, isCurrent(source), !isActivePersonScope(in: freshPersons) {
            await select(.inbox)
            return
        }
        rebuild()
    }

    /// The server's part of a load: the inbox (only "new" on a tick, whole when needed) or one list.
    private func loadServerList(
        _ source: Source, movingOnly: Bool, load: Int, wasQueued: Set<UUID>
    ) async throws(DocumentsError) {
        switch source {
        case .inbox:
            let wholeInbox = movingOnly
                ? try await loadInbox([.new], withCounts: false, load: load, wasQueued: wasQueued) : true
            if wholeInbox {
                _ = try await loadInbox(Self.inboxStates, withCounts: true, load: load, wasQueued: wasQueued)
            }
        case let .list(filter):
            let listed = try await documents.list(filter: filter)
            // The queue may have moved on while the server answered.
            queued = await uploads.items().filter { $0.workspaceID == documents.workspaceID }
            if owns(load, source) {
                serverDocuments = listed
                state = .loaded
            }
        }
    }

    /// Whether `load` is the latest load and `source` still belongs to the current scope.
    private func owns(_ load: Int, _ source: Source) -> Bool {
        load == latestLoad && isCurrent(source)
    }

    /// Replaces the letters of `states` with the server's lists. `true` when the inbox must be loaded whole: a
    /// letter that was "new" is no longer in the fresh "new" list, or a scan of `wasQueued` left the queue and
    /// is nowhere in the inbox (the server read it before this phone saw it as "new").
    private func loadInbox(
        _ states: [InboxState], withCounts: Bool, load: Int, wasQueued: Set<UUID>
    ) async throws(DocumentsError) -> Bool {
        let answer = try await Self.fetchInbox(states, withCounts: withCounts, from: documents)
        // The queue may have moved on while the server answered.
        queued = await uploads.items().filter { $0.workspaceID == documents.workspaceID }
        guard owns(load, .inbox) else { return false }
        let wasNew = Set(serverDocuments.filter { $0.inboxState == .new }.map(\.id))
        var kept = serverDocuments.filter { !states.contains($0.inboxState) }
        for state in states {
            let listed = (answer.lists[state] ?? []).filter { document in !kept.contains { $0.id == document.id } }
            kept += listed
            inboxTotals[state] = Self.total(
                fetched: answer.fetched[state] ?? 0, shown: listed.count,
                counted: withCounts ? answer.counts?.count(of: state) : inboxTotals[state]
            )
        }
        serverDocuments = kept
        state = .loaded
        guard states != Self.inboxStates else { return false }
        let isNew = Set(kept.filter { $0.inboxState == .new }.map(\.id))
        let leftQueue = wasQueued.subtracting(queued.map(\.id))
        return !wasNew.isSubset(of: isNew) || !leftQueue.isSubset(of: kept.map(\.clientID))
    }

    /// `true` when the load stops here (it went back to the inbox).
    private func handleFailure(_ error: DocumentsError, source: Source, load: Int) async -> Bool {
        switch error {
        case .revoked:
            onRevoked()
        case .missingPairing:
            onMissingPairing()
        case .cancelled:
            break
        case .notFound where owns(load, source) && scope.isPerson:
            // The person is gone: back to the inbox rather than "this document no longer exists".
            await select(.inbox)
            return true
        default:
            if owns(load, source), state != .loaded { state = .failed(message: Self.message(for: error)) }
        }
        return false
    }

    private func rebuild() {
        let arrived = Set(serverDocuments.map(\.clientID))
        // A scan on the phone has no addressee yet: it is not under a person.
        let waiting = scope.showsQueue ? waitingRows(arrived: arrived) : []
        let onServer = serverDocuments.map { Self.row(for: $0, persons: persons, labels: labels) }
        rows = arrange(waiting: waiting, onServer: onServer)
        summary = scope == .inbox
            ? Self.todoSummary(waiting: waiting, onServer: serverDocuments.map(\.inboxState), totals: inboxTotals)
            : nil
    }

    private func waitingRows(arrived: Set<UUID>) -> [Row] {
        queued
            .filter { !arrived.contains($0.id) }
            .map { item in
                Row(
                    id: item.id, documentID: nil, title: DocumentStrings.newDocument,
                    subtitle: Self.subtitle(date: item.createdAt, pages: item.pageCount),
                    status: status(of: item), date: item.createdAt
                )
            }
    }

    /// A letter's row in the words of the list; the search shows its hits with the same row.
    static func row(for document: DocumentSummary, persons: [Person], labels: [DocumentLabel]) -> Row {
        let addressees = Set(document.addresseeIDs)
        let labelIDs = Set(document.labelIDs)
        let status = Self.status(of: document)
        let (title, isProposal) = Self.title(of: document, status: status)
        return Row(
            id: document.id, documentID: document.id, title: title,
            subtitle: Self.subtitle(date: document.createdAt, pages: document.pageCount),
            status: status,
            addressees: persons.filter { addressees.contains($0.id) }.map(\.displayName),
            labels: labels.filter { labelIDs.contains($0.id) },
            hasSuggestions: document.openSuggestionCount > 0,
            isAutomatic: document.isAutomatic, titleIsProposal: isProposal,
            date: document.createdAt
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

    /// What a letter on the server needs. A read letter on nobody's name says "Naam kiezen" in every scope, as
    /// in the web: "Klaar" only when nothing waits.
    static func status(of document: DocumentSummary) -> RowStatus {
        switch document.status {
        case .processing: .processing
        case .needsReview: .needsReview
        case .failed: .failed
        // A status this app does not know yet is at least a document that can be opened.
        case .done, .unknown: document.inboxState == .unassigned ? .needsName : .done
        }
    }
}

// Polling, the camera and the queue buttons: kept out of the class body, which holds the loading.
extension DocumentsModel {
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
        await load(organisation: false)
    }

    public func deleteUpload(_ id: UUID) async {
        await uploads.delete(id)
        await load(organisation: false)
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
}
