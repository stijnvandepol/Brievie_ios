#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// The search results in "Alle post": the rows of the post list, each with the fragment where the words were
/// found, and a clear word for every state (nothing typed, too short, searching, nothing found, failed).
struct DocumentSearchList<Destination: View>: View {
    let model: DocumentSearchModel
    let destination: (UUID) -> Destination

    var body: some View {
        List {
            notices
            switch model.state {
            case .idle:
                Section { explanation(DocumentStrings.searchEmptyTitle, DocumentStrings.searchEmptyHint) }
            case .tooShort:
                Section { Text(DocumentStrings.searchTooShort).foregroundStyle(.secondary) }
            case .noResults:
                Section { explanation(DocumentStrings.searchNoneTitle, DocumentStrings.searchNoneHint) }
            case let .failed(message):
                Section {
                    ErrorBanner(message, actionTitle: DocumentStrings.retry) { model.retry() }
                }
            case .searching, .results:
                results
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder private var notices: some View {
        if model.bsnRemoved || model.isFuzzy {
            Section {
                if model.bsnRemoved { ErrorBanner(DocumentStrings.searchBSNRemoved, style: .warning) }
                if model.isFuzzy { Text(DocumentStrings.searchFuzzy).foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder private var results: some View {
        if model.state == .searching {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(DocumentStrings.searchSearching)
                }
                .accessibilityElement(children: .combine)
            }
        }
        let hits = model.hits
        if !hits.isEmpty {
            Section {
                ForEach(hits) { hit in
                    hitRow(hit)
                }
                if model.canLoadMore || model.isLoadingMore {
                    Button {
                        Task { await model.loadMore() }
                    } label: {
                        if model.isLoadingMore { ProgressView() } else { Text(DocumentStrings.searchMore) }
                    }
                    .disabled(model.isLoadingMore)
                }
            } header: {
                Text(DocumentStrings.searchResults)
            }
        }
    }

    @ViewBuilder
    private func hitRow(_ hit: DocumentSearchModel.Hit) -> some View {
        if let documentID = hit.row.documentID {
            NavigationLink {
                destination(documentID)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    DocumentRowView(row: hit.row)
                    if !hit.snippet.isEmpty {
                        Text(Self.fragment(hit.snippet))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(hit.snippetText)
                    }
                }
            }
        }
    }

    /// A centred title and hint, as the empty "Te doen" shows them.
    private func explanation(_ title: String, _ hint: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(hint)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    /// The fragment with the matched words in bold (never only colour).
    static func fragment(_ parts: [SnippetPart]) -> AttributedString {
        parts.reduce(into: AttributedString()) { text, part in
            var piece = AttributedString(part.text)
            if part.isHit {
                piece.inlinePresentationIntent = .stronglyEmphasized
                piece.foregroundColor = .primary
            }
            text += piece
        }
    }
}

/// The system search field, only in "Alle post". Return searches at once; typing searches after a pause.
struct SearchField: ViewModifier {
    let search: DocumentSearchModel
    let isAvailable: Bool

    func body(content: Content) -> some View {
        if isAvailable {
            @Bindable var search = search
            content
                .searchable(
                    text: $search.query, placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: DocumentStrings.searchPrompt
                )
                // The keyboard does not learn what is searched for in letters.
                .autocorrectionDisabled()
                .onSubmit(of: .search) { search.submit() }
        } else {
            content
        }
    }
}
#endif
