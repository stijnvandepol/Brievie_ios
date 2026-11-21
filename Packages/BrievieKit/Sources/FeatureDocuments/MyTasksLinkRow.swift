#if os(iOS)
import BrievieUI
import SwiftUI

/// The row on top of the Inbox that opens "Mijn taken": late in the warning colour, with a symbol and in words.
struct MyTasksLinkRow: View {
    let link: DocumentsModel.MyTasksLink
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack {
                Label(link.text, systemImage: symbol)
                    .font(.headline)
                    .foregroundStyle(link.isLate ? BrievieColor.warning : BrievieColor.brand)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
        }
        .accessibilityLabel(link.text)
    }

    private var symbol: String {
        if link.isLate { return "exclamationmark.triangle.fill" }
        return "checklist"
    }
}
#endif
