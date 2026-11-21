#if os(iOS)
import BrievieCore
import BrievieScan
import BrievieUI
import PhotosUI
import SwiftUI

/// The post of one workspace, with a button to scan a new letter. The app's root screen: the app adds the
/// settings button to its navigation bar.
public struct DocumentsView<Destination: View, Compare: View>: View {
    private let model: DocumentsModel
    private let scanModel: ScanFlowModel
    /// The workspace's name: the header of the scope menu.
    private let title: String
    /// The workspace's name when the user has more than one, so the screen says which post this is; `nil` with one.
    private let workspaceName: String?
    /// A warning above the post (the device has no passcode); `nil` for none.
    private let warning: String?
    /// What a document on the server opens (the review screen).
    private let destination: (UUID) -> Destination
    /// What a pair in "Dubbel?" opens (the compare screen).
    private let compare: (UUID) -> Compare

    @State private var showsScanner = false
    @State private var showsPhotoPicker = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    /// Made once per push of the Prullenbak screen.
    @State private var trashModel: TrashModel?
    /// Made once, on the first show of "Mijn taken".
    @State private var myTasksModel: MyTasksModel?
    @Environment(\.scenePhase) private var scenePhase

    public init(
        model: DocumentsModel,
        scanModel: ScanFlowModel,
        title: String,
        workspaceName: String? = nil,
        warning: String? = nil,
        @ViewBuilder destination: @escaping (UUID) -> Destination,
        @ViewBuilder compare: @escaping (UUID) -> Compare
    ) {
        self.model = model
        self.scanModel = scanModel
        self.title = title
        self.workspaceName = workspaceName
        self.warning = warning
        self.destination = destination
        self.compare = compare
    }

    public var body: some View {
        @Bindable var model = model
        content
            .modifier(SearchField(search: model.search, isAvailable: model.searchIsAvailable))
            .navigationTitle(navigationTitle)
            .workspaceSubtitle(workspaceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleMenu { scopeMenu }
            .toolbar {
                if model.canScan {
                    ToolbarItem(placement: .primaryAction) { scanButton }
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
            .navigationDestination(isPresented: $model.isShowingTrash) {
                if let trashModel { TrashView(model: trashModel) }
            }
            // A letter opened by a tapped reminder (or again after "Ongedaan maken").
            .navigationDestination(item: $model.openedDocument) { documentID in
                destination(documentID)
            }
            // The undo row appears while the letter screen closes: VoiceOver says so, or it is easily missed.
            .onChange(of: model.undo?.documentID) { _, id in
                if id != nil { AccessibilityNotification.Announcement(DocumentStrings.undoTrashed).post() }
            }
            // The post list does not refresh itself behind "Mijn taken".
            .onChange(of: model.isShowingMyTasks) { _, isShowing in
                if isShowing { model.stopPolling() } else { model.startPolling() }
            }
            .onChange(of: scanModel.phase) { _, phase in
                guard phase == .finished else { return }
                scanModel.reset()
                Task { await model.load() }
            }
    }

    /// "Mijn taken"; the search results while a term is typed in "Alle post"; otherwise the post list.
    @ViewBuilder private var content: some View {
        if model.isShowingMyTasks, let myTasksModel {
            MyTasksView(model: myTasksModel, destination: destination)
        } else if model.searchIsAvailable, model.search.isActive {
            DocumentSearchList(
                model: model.search, undo: model.undo, isUndoing: model.isUndoing,
                undoAction: { Task { await model.undoTrash() } }, closeUndo: { model.closeUndo() },
                destination: destination
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
                showAllPost: model.emptyOffersAllPost ? { Task { await model.select(.all) } } : nil
            ),
            notices: DocumentsList.Notices(
                warning: warning, camera: model.cameraNotice, removed: model.removedNotice,
                undo: model.undo, isUndoing: model.isUndoing, duplicate: model.duplicateNotice,
                openSettings: { model.openSettings() }, importPhotos: { showsPhotoPicker = true },
                undoAction: { Task { await model.undoTrash() } }, closeUndo: { model.closeUndo() },
                closeDuplicate: { model.closeDuplicateNotice() }
            ),
            myTasksLink: model.myTasksLink,
            showMyTasks: showMyTasks,
            retryLoad: { Task { await model.load() } },
            retryUpload: { id in Task { await model.retryUpload(id) } },
            deleteUpload: { id in Task { await model.deleteUpload(id) } },
            destination: destination,
            compare: compare
        )
    }

    private var navigationTitle: String {
        var hasSubtitle = false
        if #available(iOS 26, *) { hasSubtitle = true }
        return DocumentStrings.navigationTitle(
            scope: model.screenTitle, workspace: workspaceName, hasSubtitle: hasSubtitle
        )
    }

    /// "Mijn taken" (with its count) above "Inbox", "Alle post" or the post of one person; the current one is
    /// ticked. Then "Prullenbak".
    @ViewBuilder private var scopeMenu: some View {
        Section(title) {
            if model.hasMyTasks {
                Button(action: showMyTasks) {
                    Label(model.myTasksMenuTitle, systemImage: myTasksSymbol)
                }
            }
            Picker(
                selection: Binding<DocumentsModel.Scope?>(
                    get: { model.isShowingMyTasks ? nil : model.scope },
                    set: { scope in if let scope { Task { await model.select(scope) } } }
                )
            ) {
                ForEach(model.scopeTitles, id: \.0) { scope, name in
                    Text(name).tag(Optional(scope))
                }
            } label: {
                Text(model.screenTitle)
            }
            .pickerStyle(.inline)
        }
        if model.hasTrash {
            Section {
                Button(DocumentStrings.trashTitle, systemImage: "trash") {
                    trashModel = model.makeTrashModel()
                    model.isShowingTrash = true
                }
            }
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

    /// Ticked while it shows, as the picker ticks the current scope.
    private var myTasksSymbol: String {
        if model.isShowingMyTasks { return "checkmark" }
        return "checklist"
    }

    private func showMyTasks() {
        if myTasksModel == nil { myTasksModel = model.makeMyTasksModel() }
        model.showMyTasks()
    }

    /// Opens the scan's preview, which reads and turns the pages first.
    private func save(_ pages: [PageSource?]) {
        guard !pages.isEmpty else { return }
        scanModel.start(loaded: pages)
    }
}
#endif
