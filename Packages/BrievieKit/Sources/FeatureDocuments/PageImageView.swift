#if os(iOS)
import SwiftUI
import UIKit

/// One page of the letter in the review: the image, a note when it cannot be shown, or a placeholder while
/// it loads.
struct PageImageView: View {
    let data: Data?
    let label: String

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(label)
            } else if data != nil {
                // Loaded, but not an image this phone can show.
                Label(DocumentStrings.pageUnreadable, systemImage: "photo")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(label). \(DocumentStrings.pageUnreadable)")
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(DocumentStrings.pageLoading)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 32)
    }
}
#endif
