#if canImport(UIKit) && canImport(VisionKit)
import SwiftUI
import VisionKit

/// The iOS document scanner (edge detection, several pages).
///
/// Each page is handed over as compressed data, read from the scan one at a time, so a scan of many pages
/// never sits in memory as full-size bitmaps.
public struct DocumentScannerView: UIViewControllerRepresentable {
    private let onFinish: ([PageSource]) -> Void
    private let onCancel: () -> Void

    /// Not available in the simulator or on a device without a camera.
    public static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    public init(onFinish: @escaping ([PageSource]) -> Void, onCancel: @escaping () -> Void) {
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    public func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    public func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel)
    }

    public final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onFinish: ([PageSource]) -> Void
        private let onCancel: () -> Void

        init(onFinish: @escaping ([PageSource]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        public func documentCameraViewController(
            _ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
        ) {
            var pages: [PageSource] = []
            for index in 0..<scan.pageCount {
                // High quality here; the upload encoder scales and compresses once more.
                if let data = scan.imageOfPage(at: index).jpegData(compressionQuality: 0.9) {
                    pages.append(.encodedData(data))
                }
            }
            onFinish(pages)
        }

        public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        public func documentCameraViewController(
            _ controller: VNDocumentCameraViewController, didFailWithError error: any Error
        ) {
            onCancel()
        }
    }
}
#endif
