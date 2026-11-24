#if os(iOS)
import SwiftUI

/// A quick action: a round brand-coloured button with its name under it ("Scannen", "Zoeken", "Alles gelezen").
/// At the accessibility text sizes it becomes a full-width row (a small circle and the name next to it), so the name
/// is never cut. One VoiceOver element: the name, or a longer label when the name alone is not enough.
public struct RoundActionButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var diameter = BrievieRadius.roundAction
    private let title: String
    private let systemImage: String
    private let accessibilityText: String?
    private let action: () -> Void

    public init(_ title: String, systemImage: String, accessibilityLabel: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        accessibilityText = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 12) {
                    circle(size: 44)
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .brievieCard()
            } else {
                VStack(spacing: 6) {
                    circle(size: diameter)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minWidth: diameter)
            }
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText ?? title)
        .accessibilityAddTraits(.isButton)
    }

    private func circle(size: CGFloat) -> some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(BrievieColor.onBrand)
            .frame(width: size, height: size)
            .background(BrievieColor.brand, in: Circle())
    }
}

/// Round actions in one row, spread over the width; one under the other at the accessibility text sizes.
public struct RoundActionBar<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) { content }
        } else {
            HStack(alignment: .top, spacing: 24) { content }
                .frame(maxWidth: .infinity)
        }
    }
}

#if DEBUG
private struct RoundActionPreview: View {
    var body: some View {
        ScrollView {
            RoundActionBar {
                RoundActionButton("Scannen", systemImage: "doc.viewfinder", action: {})
                RoundActionButton("Zoeken", systemImage: "magnifyingglass", action: {})
                RoundActionButton("Alles gelezen", systemImage: "envelope.open", action: {})
                    .disabled(true)
            }
            .padding()
        }
        .background(BrievieColor.surface)
    }
}

#Preview("Light") { RoundActionPreview() }
#Preview("Dark") { RoundActionPreview().preferredColorScheme(.dark) }
#Preview("AX5") { RoundActionPreview().dynamicTypeSize(.accessibility5) }
#endif
#endif
