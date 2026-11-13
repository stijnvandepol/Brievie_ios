#if os(iOS)
import SwiftUI
import VisionKit

/// Scans QR codes with the camera and reports their text. Only shown once the pairing model has found
/// the camera usable (`CameraAccess`); `onFailure` reports a scanner that still cannot start.
struct QRScannerView: UIViewControllerRepresentable {
    let onScan: @MainActor (String) -> Void
    let onFailure: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onFailure: onFailure)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        context.coordinator.onFailure = onFailure
        context.coordinator.startIfNeeded(scanner)
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: @MainActor (String) -> Void
        var onFailure: @MainActor () -> Void
        private var reportedFailure = false

        init(onScan: @escaping @MainActor (String) -> Void, onFailure: @escaping @MainActor () -> Void) {
            self.onScan = onScan
            self.onFailure = onFailure
        }

        func startIfNeeded(_ scanner: DataScannerViewController) {
            guard !scanner.isScanning, !reportedFailure else { return }
            do {
                try scanner.startScanning()
            } catch {
                reportedFailure = true
                // The model changes state, and this runs inside a view update: report on the next turn.
                Task { @MainActor [onFailure] in onFailure() }
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            report(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            report([item])
        }

        private func report(_ items: [RecognizedItem]) {
            for case .barcode(let barcode) in items {
                if let text = barcode.payloadStringValue {
                    onScan(text)
                }
            }
        }
    }
}
#endif
