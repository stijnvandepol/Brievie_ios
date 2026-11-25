#if os(iOS)
import SwiftUI
import UIKit

/// The app's calm look (navigation design, section "Visuele stijl app"): screens on the grouped background,
/// summaries in rounded cards, large bold numbers, and the web's warning colour for what is late, always with
/// words next to it. A screen adopts these when it is touched; the rest keeps its look until then.
public extension BrievieColor {
    /// The screen behind the cards.
    static let surface = Color(uiColor: .systemGroupedBackground)
    /// A card on `surface`.
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    /// The web's warning text colour `#8A3707` (light); a light orange `#FFB27D` that keeps 4.5:1 on the dark card.
    static let warning = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xFF / 255, green: 0xB2 / 255, blue: 0x7D / 255, alpha: 1)
            : UIColor(red: 0x8A / 255, green: 0x37 / 255, blue: 0x07 / 255, alpha: 1)
    })
    /// The dot of an unread letter: the brand colour, never alone (the row's title is bold and VoiceOver says
    /// "Ongelezen").
    static let unread = brand
}

public enum BrievieRadius {
    /// A card's corners.
    public static let card: CGFloat = 16
    /// A round quick-action button's diameter (scaled with Dynamic Type where it is used).
    public static let roundAction: CGFloat = 56
}

public extension View {
    /// A summary card: padded, on the card colour, rounded, without a border; a soft shadow in light mode only.
    func brievieCard() -> some View {
        modifier(CardStyle())
    }

    /// A number or amount in the app's number style: bold with digits of one width, scaling with Dynamic Type.
    func brievieNumber(_ style: Font.TextStyle = .title3) -> some View {
        font(.system(style, weight: .bold)).monospacedDigit()
    }
}

private struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BrievieColor.card, in: RoundedRectangle(cornerRadius: BrievieRadius.card, style: .continuous))
            .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.06), radius: 8, y: 2)
    }
}

#Preview {
    VStack(spacing: 16) {
        VStack(alignment: .leading) {
            Text(verbatim: "€ 1.234,56").brievieNumber()
            Text(verbatim: "3 dagen te laat").foregroundStyle(BrievieColor.warning)
        }
        .brievieCard()
    }
    .padding()
    .background(BrievieColor.surface)
}
#endif
