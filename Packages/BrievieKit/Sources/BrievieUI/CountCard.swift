#if os(iOS)
import SwiftUI

/// A large number with a caption under it, on a card, tappable to its list ("4 / ongelezen"). One VoiceOver element
/// whose label says the whole thing in words ("4 ongelezen brieven in Mijn post"); the warning colour of `detail` is
/// never the only sign (its words say it).
public struct CountCard: View {
    private let number: Int
    private let caption: String
    private let detail: String?
    private let detailIsWarning: Bool
    private let accessibilityText: String
    private let action: () -> Void

    public init(
        number: Int, caption: String, detail: String? = nil, detailIsWarning: Bool = false,
        accessibilityLabel: String, action: @escaping () -> Void
    ) {
        self.number = number
        self.caption = caption
        self.detail = detail
        self.detailIsWarning = detailIsWarning
        accessibilityText = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(number, format: .number)
                    .brievieNumber(.largeTitle)
                    .foregroundStyle(.primary)
                Text(caption)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(detailIsWarning ? BrievieColor.warning : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.leading)
            .brievieCard()
            .contentShape(RoundedRectangle(cornerRadius: BrievieRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }
}

/// Count cards side by side; one under the other at the accessibility text sizes, where two would not fit.
public struct CountCardRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) { content }
        } else {
            HStack(alignment: .top, spacing: 12) { content }
        }
    }
}

#if DEBUG
private struct CountCardPreview: View {
    var body: some View {
        ScrollView {
            CountCardRow {
                CountCard(number: 4, caption: "ongelezen", accessibilityLabel: "4 ongelezen brieven", action: {})
                CountCard(
                    number: 2, caption: "taken", detail: "1 te laat", detailIsWarning: true,
                    accessibilityLabel: "2 taken, waarvan 1 te laat", action: {}
                )
            }
            .padding()
        }
        .background(BrievieColor.surface)
    }
}

#Preview("Light") { CountCardPreview() }
#Preview("Dark") { CountCardPreview().preferredColorScheme(.dark) }
#Preview("AX5") { CountCardPreview().dynamicTypeSize(.accessibility5) }
#endif
#endif
