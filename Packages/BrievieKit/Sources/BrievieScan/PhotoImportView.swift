#if canImport(UIKit) && canImport(PhotosUI)
import PhotosUI
import SwiftUI

/// Picks page photos from the photo library: the way in where the scanner is not available (the
/// simulator, a device without a camera).
public struct PhotoImportButton<Label: View>: View {
    private let maxPages: Int
    private let onFinish: ([PageSource]) -> Void
    private let label: () -> Label

    @State private var selection: [PhotosPickerItem] = []
    @State private var isPresented = false

    public init(maxPages: Int, onFinish: @escaping ([PageSource]) -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.maxPages = maxPages
        self.onFinish = onFinish
        self.label = label
    }

    public var body: some View {
        Button(action: { isPresented = true }, label: label)
            .photosPicker(
                isPresented: $isPresented, selection: $selection, maxSelectionCount: maxPages, matching: .images
            )
            .onChange(of: selection) { _, items in
                guard !items.isEmpty else { return }
                selection = []
                Task {
                    var pages: [PageSource] = []
                    for item in items {
                        // The original bytes (HEIC or JPEG) with their orientation; decoded later, scaled down.
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            pages.append(.encodedData(data))
                        }
                    }
                    onFinish(pages)
                }
            }
    }
}
#endif
