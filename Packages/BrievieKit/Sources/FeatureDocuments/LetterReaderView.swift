#if os(iOS)
import BrievieUI
import SwiftUI
import UIKit

/// The letter on the whole screen, pushed from the review or the confirmed letter (so it stays under the lock
/// screen). "Pagina": swipe through the pages, pinch or double tap to zoom; a zoomed page pans instead of
/// turning. "Tekst": the recognised text of every page as real text, the path for VoiceOver.
struct LetterReaderView: View {
    /// The pages, their texts and the page loading stay with the review.
    let review: ReviewModel
    @Bindable var reader: LetterReaderModel

    var body: some View {
        Group {
            switch reader.mode {
            case .page: pages
            case .text: texts
            }
        }
        .navigationTitle(DocumentStrings.readerTitle)
        .navigationBarTitleDisplayMode(.inline)
        // Its own close button: the back button's edge swipe would compete with turning the page.
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(DocumentStrings.scanClose) { review.closeReader() }
            }
            ToolbarItem(placement: .principal) {
                Picker(DocumentStrings.readerMode, selection: $reader.mode) {
                    Text(DocumentStrings.readerModePage).tag(LetterReaderModel.Mode.page)
                    Text(DocumentStrings.readerModeText).tag(LetterReaderModel.Mode.text)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    // MARK: - Pages

    private var pages: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(1...reader.pageCount, id: \.self) { index in
                        page(index)
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: Binding(
                get: { reader.page },
                set: { if let page = $0 { reader.show(page: page) } }
            ))
            // A zoomed page pans; only at its normal size does a swipe turn the page.
            .scrollDisabled(reader.isZoomed)
            .background(Color(.secondarySystemBackground))
            pageBar
        }
    }

    @ViewBuilder private func page(_ index: Int) -> some View {
        let label = String(format: DocumentStrings.pageFormat, index, reader.pageCount)
        Group {
            if let data = review.pages[index], UIImage(data: data) != nil {
                ZoomablePageImage(
                    data: data, label: label, hint: DocumentStrings.readerPageHint,
                    isZoomed: reader.isZoomed && reader.page == index,
                    zoomDidChange: { zoomed in
                        if reader.page == index { reader.zoomDidChange(zoomed) }
                    }
                )
            } else {
                // Loading, or not an image this phone can show: as in the review.
                PageImageView(data: review.pages[index], label: label)
            }
        }
        .task { await review.loadPage(index) }
    }

    /// "Pagina 2 van 3" with buttons to the previous and next page (also for VoiceOver and Switch Control).
    private var pageBar: some View {
        HStack {
            pageButton(DocumentStrings.readerPrevious, systemImage: "chevron.left", isEnabled: reader.hasPrevious) {
                reader.previous()
            }
            Spacer(minLength: 8)
            Text(reader.pageLabel)
                .font(.subheadline)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .accessibilityShowsLargeContentViewer()
            Spacer(minLength: 8)
            pageButton(DocumentStrings.readerNext, systemImage: "chevron.right", isEnabled: reader.hasNext) {
                reader.next()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        // A bar, like a toolbar: it grows up to a point and leaves the rest of the screen to the page; a long
        // press shows its text large.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background(.bar)
    }

    private func pageButton(
        _ title: String, systemImage: String, isEnabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation { action() }
        } label: {
            Image(systemName: systemImage)
                .imageScale(.large)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(title)
        .accessibilityShowsLargeContentViewer { Label(title, systemImage: systemImage) }
        .disabled(!isEnabled)
    }

    // MARK: - Text

    private var texts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let note = review.missingPagesNote {
                    ErrorBanner(note, style: .warning)
                }
                ForEach(1...reader.pageCount, id: \.self) { index in
                    pageText(index)
                        .id(index)
                }
            }
            .scrollTargetLayout()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        // Opens at the page that was shown; reading on moves the page the image mode returns to.
        .scrollPosition(
            id: Binding(get: { reader.page }, set: { if let page = $0 { reader.show(page: page) } }),
            anchor: .top
        )
    }

    private func pageText(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: DocumentStrings.pageFormat, index, reader.pageCount))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let text = LetterReaderModel.text(ofPage: index, in: review.pageTexts) {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
            } else {
                Label(DocumentStrings.readerTextMissing, systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
