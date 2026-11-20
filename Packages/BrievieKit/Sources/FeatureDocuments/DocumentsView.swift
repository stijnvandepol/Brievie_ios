#if os(iOS)
import BrievieCore
import BrievieScan
import BrievieUI
import PhotosUI
import SwiftUI

/// The post of one workspace, with a button to scan a new letter. The app's root screen: the app adds the
/// settings button to its navigation bar.
public struct DocumentsView<Destination: View>: View {
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

    @State private var showsScanner = false
    @State private var showsPhotoPicker = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @Environment(\.scenePhase) private var scenePhase

    public init(
        model: DocumentsModel,
        scanModel: ScanFlowModel,
        title: String,
        workspaceName: String? = nil,
        warning: String? = nil,
        @ViewBuilder destination: @escaping (UUID) -> Destination
    ) {
        self.model = model
        self.scanModel = scanModel
        self.title = title
        self.workspaceName = workspaceName
        self.warning = warning
        self.destination = destination
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
            // A letter opened by a tapped reminder.
            .navigationDestination(item: $model.openedDocument) { documentID in
                destination(documentID)
            }
            .onChange(of: scanModel.phase) { _, phase in
                guard phase == .finished else { return }
                scanModel.reset()
                Task { await model.load() }
            }
    }

    /// The search results while a term is typed in "Alle post", otherwise the post list.
    @ViewBuilder private var content: some View {
        if model.searchIsAvailable, model.search.isActive {
            DocumentSearchList(model: model.search, destination: destination)
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
            empty: DocumentsList.Empty(
                text: model.emptyText, hint: model.emptyHint,
                showAllPost: model.emptyOffersAllPost ? { Task { await model.select(.all) } } : nil
            ),
            notices: DocumentsList.Notices(
                warning: warning, camera: model.cameraNotice, removed: model.removedNotice,
                openSettings: { model.openSettings() }, importPhotos: { showsPhotoPicker = true }
            ),
            retryLoad: { Task { await model.load() } },
            retryUpload: { id in Task { await model.retryUpload(id) } },
            deleteUpload: { id in Task { await model.deleteUpload(id) } },
            destination: destination
        )
    }

    private var navigationTitle: String {
        var hasSubtitle = false
        if #available(iOS 26, *) { hasSubtitle = true }
        return DocumentStrings.navigationTitle(
            scope: model.scopeTitle, workspace: workspaceName, hasSubtitle: hasSubtitle
        )
    }

    /// "Te doen", "Alle post", or the post of one person; the current one is ticked.
    private var scopeMenu: some View {
        Section(title) {
            Picker(
                selection: Binding(get: { model.scope }, set: { scope in Task { await model.select(scope) } })
            ) {
                ForEach(model.scopeTitles, id: \.0) { scope, name in
                    Text(name).tag(scope)
                }
            } label: {
                Text(model.scopeTitle)
            }
            .pickerStyle(.inline)
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
