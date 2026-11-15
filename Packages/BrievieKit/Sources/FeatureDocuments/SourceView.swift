#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// The letter text with the quote marked: where a value was read.
struct SourceView: View {
    let quote: String
    let pageTexts: [String]
    let close: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !pageTexts.contains(where: { !QuoteLocator.ranges(of: quote, in: $0).isEmpty }) {
                        ErrorBanner(DocumentStrings.sourceMissing, style: .warning)
                        Text(String(format: DocumentStrings.sourceFormat, quote))
                    }
                    ForEach(Array(pageTexts.enumerated()), id: \.offset) { index, text in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: DocumentStrings.pageFormat, index + 1, pageTexts.count))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(Self.highlighted(text, quote: quote))
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(DocumentStrings.sourceTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(DocumentStrings.scanClose, action: close)
                }
            }
        }
    }

    /// The quote in bold on a tinted background: visible without relying on colour alone.
    static func highlighted(_ text: String, quote: String) -> AttributedString {
        var attributed = AttributedString(text)
        for range in QuoteLocator.ranges(of: quote, in: text) {
            guard
                let lower = AttributedString.Index(range.lowerBound, within: attributed),
                let upper = AttributedString.Index(range.upperBound, within: attributed)
            else { continue }
            attributed[lower..<upper].backgroundColor = .yellow.opacity(0.4)
            attributed[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
            attributed[lower..<upper].underlineStyle = .single
        }
        return attributed
    }
}
#endif
