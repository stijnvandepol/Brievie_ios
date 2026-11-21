#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// The Prullenbak screen: what the trash is for, the trashed letters with their days left, "Terugzetten" for a
/// member or admin, and the line that deleting for good is done in the web. Rows do not open a letter.
public struct TrashView: View {
    private let model: TrashModel

    public init(model: TrashModel) {
        self.model = model
    }

    public var body: some View {
        // The restored row leaves the list; with large text its notice is far above: scroll up to it and say it.
        ScrollViewReader { proxy in
            list
                .onChange(of: model.notice) { _, notice in
                    guard let notice else { return }
                    withAnimation { proxy.scrollTo(Self.noticeID, anchor: .top) }
                    AccessibilityNotification.Announcement(notice).post()
                }
        }
    }

    private static var noticeID: String { "notice" }

    private var list: some View {
        List {
            if let notice = model.notice {
                Section {
                    Label(notice, systemImage: "info.circle")
                }
                .id(Self.noticeID)
            }
            switch model.state {
            case .loading:
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(DocumentStrings.loading)
                    }
                    .accessibilityElement(children: .combine)
                }
            case let .failed(message):
                Section {
                    ErrorBanner(message, actionTitle: DocumentStrings.retry) { Task { await model.load() } }
                }
            case .loaded:
                rowsSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(DocumentStrings.trashTitle)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .task { await model.load() }
    }

    private var rowsSection: some View {
        Section {
            if model.rows.isEmpty {
                Text(DocumentStrings.trashEmpty)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.rows) { row in
                    TrashRowView(row: row, canRestore: model.canRestore) {
                        Task { await model.restore(row.id) }
                    }
                }
            }
        } header: {
            Text(model.intro)
                .textCase(nil)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if let capNote = model.capNote { Text(capNote) }
                Text(model.webOnlyNote)
            }
        }
    }
}

/// One trashed letter, read by VoiceOver as one element; "Terugzetten" stays its own button.
private struct TrashRowView: View {
    let row: TrashModel.Row
    let canRestore: Bool
    let restore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.headline)
                if let detail = row.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(row.deletedLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label(row.daysLeftLine, systemImage: "clock")
                    .font(.subheadline)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            if canRestore {
                Button(DocumentStrings.trashRestore, systemImage: "arrow.uturn.backward", action: restore)
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                    .accessibilityLabel(row.restoreLabel)
            }
        }
        .padding(.vertical, 4)
    }
}
#endif
