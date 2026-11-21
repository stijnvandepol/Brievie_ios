#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// The rendering of `DocumentsView`, free of the models so that previews can feed it plain values.
struct DocumentsList<Destination: View>: View {
    /// Messages above the list: no passcode, no camera access, scans the queue could not read.
    struct Notices {
        var warning: String?
        var camera: DocumentsModel.CameraNotice?
        var removed: String?
        /// After a letter went to the trash: "Ongedaan maken" and "Sluiten".
        var undo: DocumentsModel.UndoNotice?
        var openSettings: () -> Void = {}
        var importPhotos: () -> Void = {}
        var undoAction: () -> Void = {}
        var closeUndo: () -> Void = {}
    }

    /// What the list says without rows: depends on the scope.
    struct Empty {
        var text: String
        /// What to do next ("Te doen" only).
        var hint: String?
        /// "Bekijk Alle post" ("Te doen" only); `nil` shows no button.
        var showAllPost: (() -> Void)?
    }

    let state: DocumentsModel.State
    let rows: [DocumentsModel.Row]
    /// Above the rows: how many need what ("Te doen" only).
    var summary: String?
    /// Under the rows: what this place is for.
    var footer: String?
    let empty: Empty
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
            if rows.isEmpty {
                Section {
                    placeholder
                }
            } else {
                Section {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                } header: {
                    if let summary { Text(summary) }
                } footer: {
                    if let footer { Text(footer) }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder private var noticeSection: some View {
        if notices.warning != nil || notices.camera != nil || notices.removed != nil || notices.undo != nil {
            Section {
                if let warning = notices.warning {
                    ErrorBanner(warning, style: .warning)
                }
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
                if let undo = notices.undo {
                    UndoRow(notice: undo, undo: notices.undoAction, close: notices.closeUndo)
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
        case .loaded where empty.hint != nil:
            // "Te doen" is empty: done, with what to do next and the way to the rest of the post. Not
            // `ContentUnavailableView`: it cuts its title to one line.
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(empty.text)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(empty.hint ?? "")
                    .foregroundStyle(.secondary)
                if let showAllPost = empty.showAllPost {
                    Button(DocumentStrings.showAllPost, action: showAllPost)
                        .buttonStyle(.borderless)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        case .loaded:
            Text(empty.text)
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

/// "De brief staat in de prullenbak." with "Ongedaan maken" and "Sluiten"; why the undo failed under it. The
/// buttons stand side by side, or one under the other when the text is large.
private struct UndoRow: View {
    let notice: DocumentsModel.UndoNotice
    let undo: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(notice.message, systemImage: "trash")
                .fixedSize(horizontal: false, vertical: true)
            if let failure = notice.failure {
                ErrorBanner(failure)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { buttons }
                VStack(alignment: .leading, spacing: 8) { buttons }
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        Button(DocumentStrings.undoAction, action: undo)
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
        Button(DocumentStrings.undoClose, action: close)
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
    }
}

#if DEBUG
private var previewRows: [DocumentsModel.Row] {
    [
        .init(
            id: UUID(), documentID: UUID(), title: "Belastingdienst", subtitle: "13 nov 2026 · 1 pagina",
            status: .needsReview
        ),
        .init(
            id: UUID(), documentID: UUID(), title: "CAK", subtitle: "10 nov 2026 · 3 pagina's", status: .needsName,
            labels: [
                DocumentLabel(id: UUID(), name: "Zorg", colorKey: "green"),
                DocumentLabel(id: UUID(), name: "Belasting en toeslagen", colorKey: "blue")
            ],
            hasSuggestions: true
        ),
        .init(
            id: UUID(), documentID: nil, title: "Nieuwe brief", subtitle: "14 nov 2026 · 2 pagina's",
            status: .uploadFailed(message: "Uploaden is niet gelukt.")
        ),
        .init(
            id: UUID(), documentID: nil, title: "Nieuwe brief", subtitle: "14 nov 2026 · 2 pagina's",
            status: .uploading(progress: 0.4)
        ),
        .init(
            id: UUID(), documentID: UUID(), title: "Nieuwe brief", subtitle: "14 nov 2026 · 1 pagina",
            status: .processing
        )
    ]
}

private var previewEmpty: DocumentsList<EmptyView>.Empty {
    .init(
        text: "Je bent klaar. Er is niets te doen.",
        hint: "Een nieuwe brief scan je met de knop + bovenaan. Eerdere brieven vind je bij Alle post.",
        showAllPost: {}
    )
}

#Preview("Te doen") {
    NavigationStack {
        DocumentsList(
            state: .loaded, rows: previewRows,
            summary: "Controleren: 1 · Naam kiezen: 1 · Upload mislukt: 1 · Bezig: 2",
            footer: "Brieven waar jij nog iets mee moet doen. Al je brieven, ook de afgehandelde, staan bij Alle post.",
            empty: previewEmpty, retryLoad: {}, retryUpload: { _ in }, deleteUpload: { _ in },
            destination: { _ in EmptyView() }
        )
        .navigationTitle("Te doen")
        .workspaceSubtitle("Thuis")
        .navigationBarTitleDisplayMode(.inline)
    }
    .tint(BrievieColor.brand)
}

#Preview("Empty, dark, no passcode") {
    NavigationStack {
        DocumentsList(
            state: .loaded, rows: [], empty: previewEmpty,
            notices: .init(warning: "Dit apparaat heeft geen toegangscode. Stel een toegangscode in."),
            retryLoad: {}, retryUpload: { _ in }, deleteUpload: { _ in }, destination: { _ in EmptyView() }
        )
        .navigationTitle("Te doen")
        .navigationBarTitleDisplayMode(.inline)
    }
    .tint(BrievieColor.brand)
    .preferredColorScheme(.dark)
}
#endif
#endif
