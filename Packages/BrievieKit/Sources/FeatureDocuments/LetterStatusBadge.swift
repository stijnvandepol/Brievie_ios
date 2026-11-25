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
                Label(DocumentStrings.letterStatusOverdue, systemImage: "exclamationmark.triangle.fill")
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
