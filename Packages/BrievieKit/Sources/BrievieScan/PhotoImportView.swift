#if canImport(UIKit) && canImport(PhotosUI)
import PhotosUI
import SwiftUI

/// Pages picked from the photo library: the way in next to the scanner, and the only one where the scanner
/// cannot be used (the simulator, a device without a camera).
public enum PhotoPages {
    /// The original bytes of each photo (HEIC or JPEG) with their orientation; decoded later, scaled down.
    public static func load(_ items: [PhotosPickerItem]) async -> [PageSource] {
        var pages: [PageSource] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                pages.append(.encodedData(data))
            }
        }
        return pages
    }
}
#endif
