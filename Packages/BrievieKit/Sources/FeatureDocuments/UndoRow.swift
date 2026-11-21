#if os(iOS)
import BrievieUI
import SwiftUI

/// "De brief staat in de prullenbak." with "Ongedaan maken" and "Sluiten"; why the undo failed under it. The
/// buttons stand side by side, or one under the other when the text is large.
struct UndoRow: View {
    let notice: DocumentsModel.UndoNotice
    let isUndoing: Bool
    let undo: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(notice.message, systemImage: "trash")
                .fixedSize(horizontal: false, vertical: true)
            if let failure = notice.failure {
                ErrorBanner(failure)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { buttons }
                VStack(alignment: .leading, spacing: 8) { buttons }
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        Button(DocumentStrings.undoAction, action: undo)
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
            .disabled(isUndoing)
        Button(DocumentStrings.undoClose, action: close)
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
    }
}
#endif
