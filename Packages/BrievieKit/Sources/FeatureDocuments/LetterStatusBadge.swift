#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// The letter's status as a small capsule, and "Te laat" in the warning colour next to it (always in words).
struct LetterStatusBadge: View {
    let badge: LetterBadge
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At an accessibility size the badge may wrap ("Wacht op reactie tot 5 dec" is long): fixed at its ideal
        // width it made the whole row wider than the screen and cut every line off at both sides.
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) { parts }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(badge.accessibilityText)
        } else {
            HStack(spacing: 4) { parts }
                .fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(badge.accessibilityText)
        }
    }

    private var color: Color { badge.status == .handled ? Color.secondary : BrievieColor.brand }

    @ViewBuilder private var parts: some View {
        Text(badge.text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(color))
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
}
#endif
