#if os(iOS)
import BrievieUI
import SwiftUI

/// Shown while a scan is turned into an upload: which page is being read, or what went wrong.
struct ScanFlowView: View {
    let phase: ScanFlowModel.Phase
    let close: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch phase {
                case let .failed(message):
                    ErrorBanner(message)
                    PrimaryButton(DocumentStrings.scanClose, action: close)
                case .idle, .recognising, .finished:
                    ProgressView()
                    Text(phase.label)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(DocumentStrings.scanTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
