#if os(iOS)
import BrievieCore
import BrievieScan
import BrievieUI
import PhotosUI
import SwiftUI

/// The post of one workspace, with a button to scan a new letter.
public struct DocumentsView<Destination: View>: View {
    private let model: DocumentsModel
    private let scanModel: ScanFlowModel
    /// The workspace's name: the header of the scope menu.
    private let title: String
    /// What a document on the server opens (the review screen).
    private let destination: (UUID) -> Destination

    @State private var showsScanner = false
    @State private var showsPhotoPicker = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var showsScanProgress = false
    @Environment(\.scenePhase) private var scenePhase

    public init(
        model: DocumentsModel,
        scanModel: ScanFlowModel,
        title: String,
        @ViewBuilder destination: @escaping (UUID) -> Destination
    ) {
        self.model = model
        self.scanModel = scanModel
        self.title = title
        self.destination = destination
    }

    public var body: some View {
        DocumentsList(
            state: model.state,
            groups: model.groups,
            emptyText: model.emptyText,
            notices: DocumentsList.Notices(
                camera: model.cameraNotice, removed: model.removedNotice,
                openSettings: { model.openSettings() }, importPhotos: { showsPhotoPicker = true }
            ),
            retryLoad: { Task { await model.load() } },
            retryUpload: { id in Task { await model.retryUpload(id) } },
            deleteUpload: { id in Task { await model.deleteUpload(id) } },
            destination: destination
        )
        .navigationTitle(model.scopeTitle)
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
        .sheet(isPresented: $showsScanProgress) {
            ScanFlowView(phase: scanModel.phase) {
                showsScanProgress = false
                scanModel.reset()
            }
            .interactiveDismissDisabled()
            .presentationDetents([.medium])
        }
    }

    /// Inbox, all post, or the post of one person; the current one is ticked.
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

    private func save(_ pages: [PageSource?]) {
        guard !pages.isEmpty else { return }
        showsScanProgress = true
        Task {
            await scanModel.process(loaded: pages)
            if scanModel.phase == .finished {
                showsScanProgress = false
                scanModel.reset()
            }
            await model.load()
        }
    }
}

/// The rendering of `DocumentsView`, free of the models so that previews can feed it plain values.
struct DocumentsList<Destination: View>: View {
    /// Messages above the list: no camera access, scans the queue could not read.
    struct Notices {
        var camera: DocumentsModel.CameraNotice?
        var removed: String?
        var openSettings: () -> Void = {}
        var importPhotos: () -> Void = {}
    }

    let state: DocumentsModel.State
    let groups: [DocumentsModel.RowGroup]
    /// What the list says without rows: depends on the scope.
    let emptyText: String
    var notices = Notices()
    let retryLoad: () -> Void
    let retryUpload: (UUID) -> Void
    let deleteUpload: (UUID) -> Void
    let destination: (UUID) -> Destination

    var body: some View {
        List {
            noticeSection
            if case let .failed(message) = state {
                Section {
                    ErrorBanner(message, actionTitle: DocumentStrings.retry, action: retryLoad)
                }
            }
            if groups.allSatisfy(\.rows.isEmpty) {
                Section {
                    placeholder
                }
            }
            ForEach(groups.filter { !$0.rows.isEmpty }) { group in
                Section {
                    ForEach(group.rows) { row in
                        rowView(row)
                    }
                } header: {
                    Text(group.header)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder private var noticeSection: some View {
        if notices.camera != nil || notices.removed != nil {
            Section {
                switch notices.camera {
                case .denied:
                    ErrorBanner(
                        DocumentStrings.cameraDenied, style: .warning, actionTitle: DocumentStrings.openSettings,
                        action: notices.openSettings
                    )
                case .restricted:
                    ErrorBanner(DocumentStrings.cameraRestricted, style: .warning)
                case nil:
                    EmptyView()
                }
                if notices.camera != nil {
                    Button(action: notices.importPhotos) {
                        Label(DocumentStrings.importPhotos, systemImage: "photo.on.rectangle")
                    }
                }
                if let removed = notices.removed {
                    ErrorBanner(removed, style: .warning)
                }
            }
        }
    }

    @ViewBuilder private var placeholder: some View {
        switch state {
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                Text(DocumentStrings.loading)
            }
            .accessibilityElement(children: .combine)
        case .loaded:
            Text(emptyText)
                .foregroundStyle(.secondary)
        case .failed:
            EmptyView()
        }
    }

    @ViewBuilder
    private func rowView(_ row: DocumentsModel.Row) -> some View {
        if let documentID = row.documentID {
            NavigationLink {
                destination(documentID)
            } label: {
                DocumentRowView(row: row)
            }
        } else {
            // Retry and delete as swipe actions, as a context menu, as VoiceOver and Switch Control actions,
            // and as visible buttons once the upload failed.
            VStack(alignment: .leading, spacing: 12) {
                DocumentRowView(row: row)
                    .accessibilityActions { uploadActions(row) }
                if case .uploadFailed = row.status {
                    failedRowButtons(row)
                }
            }
            .contextMenu { uploadActions(row) }
            .swipeActions(edge: .trailing) {
                if row.status.canDelete {
                    Button(DocumentStrings.delete, role: .destructive) { deleteUpload(row.id) }
                }
                if row.status.canRetryUpload {
                    Button(DocumentStrings.retry) { retryUpload(row.id) }
                        .tint(BrievieColor.brand)
                }
            }
        }
    }

    @ViewBuilder
    private func uploadActions(_ row: DocumentsModel.Row) -> some View {
        if row.status.canRetryUpload {
            Button {
                retryUpload(row.id)
            } label: {
                Label(DocumentStrings.retry, systemImage: "arrow.clockwise")
            }
        }
        if row.status.canDelete {
            Button(role: .destructive) {
                deleteUpload(row.id)
            } label: {
                Label(DocumentStrings.delete, systemImage: "trash")
            }
        }
    }

    /// Side by side, or stacked when the text is large.
    private func failedRowButtons(_ row: DocumentsModel.Row) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { failedButtons(row) }
            VStack(spacing: 8) { failedButtons(row) }
        }
    }

    @ViewBuilder
    private func failedButtons(_ row: DocumentsModel.Row) -> some View {
        if row.status.canRetryUpload {
            SecondaryButton(DocumentStrings.retry) { retryUpload(row.id) }
        }
        if row.status.canDelete {
            SecondaryButton(DocumentStrings.delete) { deleteUpload(row.id) }
        }
    }
}

#if DEBUG
private var previewRows: [DocumentsModel.Row] {
    [
        .init(
            id: UUID(), documentID: nil, title: "Nieuw document", subtitle: "14 nov 2026 · 2 pagina's",
            status: .uploading(progress: 0.4)
        ),
        .init(
            id: UUID(), documentID: UUID(), title: "Belastingdienst", subtitle: "13 nov 2026 · 1 pagina",
            status: .needsReview
        ),
        .init(
            id: UUID(), documentID: UUID(), title: "CAK", subtitle: "10 nov 2026 · 3 pagina's", status: .done,
            addressees: ["Papa", "Mama"],
            labels: [
                DocumentLabel(id: UUID(), name: "Zorg", colorKey: "green"),
                DocumentLabel(id: UUID(), name: "Belasting en toeslagen", colorKey: "blue"),
                DocumentLabel(id: UUID(), name: "Verzekering", colorKey: "purple")
            ],
            hasSuggestions: true
        )
    ]
}

private var previewGroups: [DocumentsModel.RowGroup] {
    [DocumentsModel.RowGroup(kind: .post, title: "Post", header: "Post", rows: previewRows)]
}

#Preview("Light") {
    NavigationStack {
        DocumentsList(
            state: .loaded, groups: previewGroups, emptyText: "", retryLoad: {}, retryUpload: { _ in },
            deleteUpload: { _ in },
            destination: { _ in EmptyView() }
        )
        .navigationTitle("Thuis")
    }
    .tint(BrievieColor.brand)
}

#Preview("Dark") {
    NavigationStack {
        DocumentsList(
            state: .loaded, groups: previewGroups, emptyText: "", retryLoad: {}, retryUpload: { _ in },
            deleteUpload: { _ in },
            destination: { _ in EmptyView() }
        )
        .navigationTitle("Thuis")
    }
    .tint(BrievieColor.brand)
    .preferredColorScheme(.dark)
}
#endif
#endif
