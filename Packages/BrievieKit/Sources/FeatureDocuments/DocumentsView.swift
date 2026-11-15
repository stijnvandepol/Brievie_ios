#if os(iOS)
import BrievieScan
import BrievieUI
import PhotosUI
import SwiftUI

/// The post of one workspace, with a button to scan a new letter.
public struct DocumentsView<Destination: View>: View {
    private let model: DocumentsModel
    private let scanModel: ScanFlowModel
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
            rows: model.rows,
            retryLoad: { Task { await model.load() } },
            retryUpload: { id in Task { await model.retryUpload(id) } },
            deleteUpload: { id in Task { await model.deleteUpload(id) } },
            destination: destination
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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

    /// Scan with the camera, or pick photos of the pages. Where the scanner is unavailable (no camera),
    /// only the photos.
    @ViewBuilder private var scanButton: some View {
        if DocumentScannerView.isSupported {
            Menu {
                Button {
                    showsScanner = true
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
    let state: DocumentsModel.State
    let rows: [DocumentsModel.Row]
    let retryLoad: () -> Void
    let retryUpload: (UUID) -> Void
    let deleteUpload: (UUID) -> Void
    let destination: (UUID) -> Destination

    var body: some View {
        List {
            if case let .failed(message) = state {
                Section {
                    ErrorBanner(message, actionTitle: DocumentStrings.retry, action: retryLoad)
                }
            }
            Section {
                if rows.isEmpty {
                    placeholder
                }
                ForEach(rows) { row in
                    rowView(row)
                }
            } header: {
                Text(DocumentStrings.section)
            }
        }
        .listStyle(.insetGrouped)
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
            Text(DocumentStrings.empty)
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
            DocumentRowView(row: row)
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
}

private struct DocumentRowView: View {
    let row: DocumentsModel.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.title)
                .font(.headline)
            Text(row.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            status
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var status: some View {
        switch row.status {
        case let .uploading(progress):
            ProgressView(value: progress) {
                Text(row.status.label)
                    .font(.subheadline)
            }
        case let .uploadFailed(message, _):
            statusLabel(color: .red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .failed:
            statusLabel(color: .red)
        case .needsReview:
            statusLabel(color: .orange)
        case .done:
            statusLabel(color: .green)
        case .waitingForUpload, .processing:
            statusLabel(color: .secondary)
        }
    }

    private func statusLabel(color: Color) -> some View {
        Label {
            Text(row.status.label)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: row.status.iconName)
                .foregroundStyle(color)
        }
        .font(.subheadline)
    }
}

/// Shown while a scan is turned into an upload: which page is being read, or what went wrong.
struct ScanFlowView: View {
    let phase: ScanFlowModel.Phase
    let close: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch phase {
                case let .failed(message):
                    ErrorBanner(message)
                    PrimaryButton(DocumentStrings.scanClose, action: close)
                case .idle, .recognising, .finished:
                    ProgressView()
                    Text(phase.label)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(DocumentStrings.scanTitle)
            .navigationBarTitleDisplayMode(.inline)
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
        .init(id: UUID(), documentID: UUID(), title: "CAK", subtitle: "10 nov 2026 · 3 pagina's", status: .done)
    ]
}

#Preview("Light") {
    NavigationStack {
        DocumentsList(
            state: .loaded, rows: previewRows, retryLoad: {}, retryUpload: { _ in }, deleteUpload: { _ in },
            destination: { _ in EmptyView() }
        )
        .navigationTitle("Thuis")
    }
    .tint(BrievieColor.brand)
}

#Preview("Dark") {
    NavigationStack {
        DocumentsList(
            state: .loaded, rows: previewRows, retryLoad: {}, retryUpload: { _ in }, deleteUpload: { _ in },
            destination: { _ in EmptyView() }
        )
        .navigationTitle("Thuis")
    }
    .tint(BrievieColor.brand)
    .preferredColorScheme(.dark)
}
#endif
#endif
