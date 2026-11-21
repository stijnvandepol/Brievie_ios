import BrievieCore
import Foundation
import Observation

/// The post of one workspace: scans still on the phone and documents on the server, with where each one is
/// on its way from scan to confirmed.
@MainActor
@Observable
public final class DocumentsModel {
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
    /// The server has a trash: "Prullenbak", "Verwijderen". False until a whole load found out (`probeTrash`).
    public internal(set) var hasTrash = false
    public internal(set) var undo: UndoNotice?
    public var isShowingTrash = false
    /// "Mijn taken" shows in place of the post list (see `+MyTasks`).
    public internal(set) var isShowingMyTasks = false
    /// The server's counts of "Mijn taken"; `nil` before the first load and against an older server.
    public internal(set) var myTaskCounts: MyTaskCounts?
    /// The server knows "Mijn taken": the title menu offers it. False until a whole load found out.
    public internal(set) var hasMyTasks = false
    /// "Dubbel?" in "Te doen": the open pairs, asked on a whole load when the server counts them (see `+Duplicates`).
    public internal(set) var duplicates: [DuplicateRow] = []
    /// "Goed. We vragen het niet meer…" after a pair was dismissed; gone on "Sluiten" or another scope.
    public internal(set) var duplicateNotice: String?
    @ObservationIgnored var pairCount = 0 // counted by the last whole inbox load (0 from a server without pairs)
    /// The number of the latest pair load: only that one writes `duplicates`.
    @ObservationIgnored var latestPairLoad = 0
    /// "Ongedaan maken" is on its way: the button waits.
    public internal(set) var isUndoing = false
    /// The letters' open tasks changed on the server (a letter went to the trash or came back): the calendar
    /// and the deadline reminders follow. Set by the screen that owns this model.
    @ObservationIgnored public var onTasksChanged: @MainActor () -> Void = {}
    /// Search in "Alle post"; forgotten when the user leaves it (and with this model, on a workspace switch or when
    /// the session ends).
    public let search: DocumentSearchModel

    let documents: WorkspaceDocuments
    private let uploads: any UploadQueue
    private let camera: any ScanCameraAccess
    private let settingsOpener: @MainActor () -> Void
    let onRevoked: @MainActor () -> Void
    let onMissingPairing: @MainActor () -> Void
    private let refreshInterval: Duration
    let locale: Locale

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
        searchDelay: Duration = DocumentSearchModel.typingPause,
        locale: Locale = .autoupdatingCurrent
    ) {
        self.documents = documents
        self.uploads = uploads
        self.canScan = canScan
        self.camera = camera
        settingsOpener = openSettings
        self.onRevoked = onRevoked
        self.onMissingPairing = onMissingPairing
        self.refreshInterval = refreshInterval
        self.locale = locale
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
        // Once the server is known to have a trash, it keeps it: no need to ask again.
        let knowsTrash = hasTrash
        async let probe = knowsTrash ? true : Self.probeTrash(documents)
        async let counts = Self.fetchMyTaskCounts(documents)
        await load(organisation: true)
        if let found = await probe { hasTrash = found }
        apply(await counts)
        await loadDuplicates()
    }

    /// Shows another scope. A scope with another server list starts empty, so no wrong post shows meanwhile.
    public func select(_ scope: Scope) async {
        isShowingMyTasks = false
        guard scope != self.scope else { return }
        undo = nil
        duplicateNotice = nil
        if scope != .inbox { duplicates = [] }
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
        let pairsBefore = pairCount
        await load(organisation: false, movingOnly: state == .loaded)
        // A tick that loaded the inbox whole may learn of a new pair (or one decided elsewhere): only then the group.
        if pairCount != pairsBefore { await loadDuplicates() }
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
        // Counts that failed say nothing about the pairs: keep the last number, so the group stays.
        if withCounts, let counts = answer.counts { pairCount = counts.duplicate }
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

    private func status(of item: UploadItem) -> RowStatus {
        switch item.state {
        case .waiting: .waitingForUpload
        case .uploading:
            // Handed to the system but nothing sent yet (offline, or scheduled for later): it waits.
            progress[item.id].map { .uploading(progress: $0) } ?? .waitingForUpload
        case .failed:
            .uploadFailed(
                message: Self.uploadMessage(for: item.failureCode),
                canRetry: !Self.finalUploadCodes.contains(item.failureCode ?? "")
            )
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
