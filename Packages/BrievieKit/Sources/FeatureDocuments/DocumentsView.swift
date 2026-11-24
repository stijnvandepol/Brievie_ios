#if os(iOS)
import BrievieCore
import BrievieScan
import BrievieUI
import PhotosUI
import SwiftUI

/// One list of a workspace's post (Inbox, Mijn post, Alle post), with a button to scan a new letter. The root of a
/// tab: the tabs add the workspace pill to its navigation bar.
public struct DocumentsView<Destination: View, Compare: View>: View {
    private let model: DocumentsModel
    private let scanModel: ScanFlowModel
    /// A warning above the post (the device has no passcode); `nil` for none.
    private let warning: String?
    /// "Mijn taken: 4 open" on top of the Inbox: the "Taken" tab.
    private let showMyTasks: () -> Void
    /// "Bekijk Alle post" under the empty Inbox.
    private let showAllPost: () -> Void
    /// Count cards and round actions on top (tab roots); `nil` for none.
    private let header: PostHeader?
    /// What a document on the server opens (the review screen).
    private let destination: (UUID) -> Destination
    /// What a pair in "Dubbel?" opens (the compare screen).
    private let compare: (UUID) -> Compare

    @State private var showsScanner = false
    @State private var showsPhotoPicker = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @Environment(\.scenePhase) private var scenePhase

    public init(
        model: DocumentsModel,
        scanModel: ScanFlowModel,
        warning: String? = nil,
        showMyTasks: @escaping () -> Void = {},
        showAllPost: @escaping () -> Void = {},
        header: PostHeader? = nil,
        @ViewBuilder destination: @escaping (UUID) -> Destination,
        @ViewBuilder compare: @escaping (UUID) -> Compare
    ) {
        self.model = model
        self.scanModel = scanModel
        self.warning = warning
        self.showMyTasks = showMyTasks
        self.showAllPost = showAllPost
        self.header = header
        self.destination = destination
        self.compare = compare
    }

    public var body: some View {
        @Bindable var model = model
        content
            .modifier(SearchField(
                search: model.search, isAvailable: model.searchIsAvailable, isPresented: $model.isSearchPresented
            ))
            .navigationTitle(model.scopeTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if model.canScan {
                    ToolbarItem(placement: .primaryAction) { scanButton }
                }
                if model.offersForWhom {
                    ToolbarItem(placement: .topBarTrailing) { forWhomMenu }
                }
                if model.isMyPost, model.offersReading {
                    ToolbarItem(placement: .topBarTrailing) { unreadOnlyButton }
                }
            }
            .refreshable { await model.load() }
            .task {
                await model.load()
                model.startPolling()
            }
            .onDisappear { model.stopPolling() }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    model.startPolling()
                    model.refreshCameraNotice()
                case .background:
                    // The scanner shows the pages scanned so far; it would sit above the lock screen.
                    showsScanner = false
                    showsPhotoPicker = false
                    model.stopPolling()
                default:
                    model.stopPolling()
                }
            }
            .fullScreenCover(isPresented: $showsScanner) {
                DocumentScannerView(
                    onFinish: { pages in
                        showsScanner = false
                        save(pages)
                    },
                    onCancel: { showsScanner = false }
                )
                .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: $showsPhotoPicker, selection: $pickedPhotos, maxSelectionCount: 30, matching: .images
            )
            .onChange(of: pickedPhotos) { _, items in
                guard !items.isEmpty else { return }
                pickedPhotos = []
                Task { save(await PhotoPages.load(items)) }
            }
            .navigationDestination(
                isPresented: Binding(get: { scanModel.isPresented }, set: { if !$0 { scanModel.discard() } })
            ) {
                ScanFlowView(model: scanModel)
            }
            // A letter opened by a tapped reminder (or again after "Ongedaan maken").
            .navigationDestination(item: $model.openedDocument) { documentID in
                destination(documentID)
            }
            // A letter opened from the search results: registered here, on the screen that stays.
            .navigationDestination(for: SearchHitLink.self) { link in
                destination(link.documentID)
            }
            // The undo row appears while the letter screen closes: VoiceOver says so, or it is easily missed.
            .onChange(of: model.undo?.documentID) { _, id in
                if id != nil { AccessibilityNotification.Announcement(DocumentStrings.undoTrashed).post() }
            }
            .onChange(of: scanModel.phase) { _, phase in
                guard phase == .finished else { return }
                scanModel.reset()
                Task { await model.load() }
            }
    }

    /// The search results while a term is typed in "Alle post"; otherwise the post list.
    @ViewBuilder private var content: some View {
        if model.searchIsAvailable, model.search.isActive {
            DocumentSearchList(
                model: model.search, undo: model.undo, isUndoing: model.isUndoing,
                undoAction: { Task { await model.undoTrash() } }, closeUndo: { model.closeUndo() }
            )
        } else {
            postList
        }
    }

    private var postList: some View {
        DocumentsList(
            state: model.state,
            rows: model.rows,
            summary: model.summary,
            footer: model.footer,
            duplicates: model.duplicates,
            empty: DocumentsList.Empty(
                text: model.emptyText, hint: model.emptyHint,
                showAllPost: model.emptyOffersAllPost ? showAllPost : nil
            ),
            notices: DocumentsList.Notices(
                warning: warning, camera: model.cameraNotice, removed: model.removedNotice,
                undo: model.undo, isUndoing: model.isUndoing, duplicate: model.duplicateNotice,
                openSettings: { model.openSettings() }, importPhotos: { showsPhotoPicker = true },
                undoAction: { Task { await model.undoTrash() } }, closeUndo: { model.closeUndo() },
                closeDuplicate: { model.closeDuplicateNotice() }
            ),
            header: header,
            scan: startScan,
            reading: model.offersReading
                ? ReadingControls(
                    markRead: { id in Task { await model.markRead(id) } },
                    markUnread: { id in Task { await model.markUnread(id) } }
                )
                : nil,
            myTasksLink: model.myTasksLink,
            showMyTasks: showMyTasks,
            retryLoad: { Task { await model.load() } },
            retryUpload: { id in Task { await model.retryUpload(id) } },
            deleteUpload: { id in Task { await model.deleteUpload(id) } },
            destination: destination,
            compare: compare
        )
    }

    private static var filterOnSymbol: String { "line.3.horizontal.decrease.circle.fill" }
    private static var filterOffSymbol: String { "line.3.horizontal.decrease.circle" }

    /// "Alleen ongelezen" in "Mijn post": on or off.
    private var unreadOnlyButton: some View {
        let isOn = model.scope == .myPostUnread
        return Button {
            Task { await model.select(isOn ? .myPost : .myPostUnread) }
        } label: {
            Label(DocumentStrings.unreadOnly, systemImage: isOn ? Self.filterOnSymbol : Self.filterOffSymbol)
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// The round "Scannen": the camera, or the photos where there is no camera.
    private func startScan() {
        guard DocumentScannerView.isSupported else {
            showsPhotoPicker = true
            return
        }
        Task {
            if await model.prepareScanner() { showsScanner = true }
        }
    }

    /// "Voor wie": everyone's post, or the post of one person (the persons who are not archived).
    private var forWhomMenu: some View {
        Menu {
            Picker(
                selection: Binding<DocumentsModel.Scope>(
                    get: { model.scope },
                    set: { scope in Task { await model.select(scope) } }
                )
            ) {
                ForEach(model.forWhomChoices, id: \.0) { scope, name in
                    Text(name).tag(scope)
                }
            } label: {
                Text(DocumentStrings.forWhom)
            }
            .pickerStyle(.inline)
        } label: {
            Label(DocumentStrings.forWhom, systemImage: "person.crop.circle")
        }
    }

    /// Scan with the camera, or pick photos of the pages. Where the scanner is unavailable (no camera),
    /// only the photos.
    @ViewBuilder private var scanButton: some View {
        if DocumentScannerView.isSupported {
            Menu {
                Button {
                    Task {
                        // Without camera access the scanner would only close again: explain instead.
                        if await model.prepareScanner() { showsScanner = true }
                    }
                } label: {
                    Label(DocumentStrings.scan, systemImage: "doc.viewfinder")
                }
                Button {
                    showsPhotoPicker = true
                } label: {
                    Label(DocumentStrings.importPhotos, systemImage: "photo.on.rectangle")
                }
            } label: {
                Label(DocumentStrings.addPost, systemImage: "plus")
            }
        } else {
            Button {
                showsPhotoPicker = true
            } label: {
                Label(DocumentStrings.importPhotos, systemImage: "photo.on.rectangle")
            }
        }
    }

    /// Opens the scan's preview, which reads and turns the pages first.
    private func save(_ pages: [PageSource?]) {
        guard !pages.isEmpty else { return }
        scanModel.start(loaded: pages)
    }
}
#endif
