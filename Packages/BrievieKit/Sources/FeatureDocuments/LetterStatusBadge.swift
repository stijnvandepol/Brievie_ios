#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// The letter's status as a small capsule, and "Te laat" in the warning colour next to it (always in words).
struct LetterStatusBadge: View {
    let badge: LetterBadge

    var body: some View {
        HStack(spacing: 4) {
            Text(badge.text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(badge.status == .handled ? Color.secondary : BrievieColor.brand)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .overlay(Capsule().stroke(badge.status == .handled ? Color.secondary : BrievieColor.brand))
            if badge.isOverdue {
                // Not a `Label`: in a list row a label takes the row's icon column, and the row fell apart
                // (the words "Te laat" gone, the badge adrift in empty space).
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(DocumentStrings.letterStatusOverdue)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(BrievieColor.warning)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.accessibilityText)
    }
}
#endif
