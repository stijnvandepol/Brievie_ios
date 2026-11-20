import SwiftUI

/// Side by side at the usual text sizes, one under the other at the accessibility sizes. A word next to an icon or
/// a chip then gets the whole width and wraps between words, instead of being broken in the middle ("Control-eren",
/// "Voors-tel": seen in the simulator at the largest size, 20-11-2026).
public struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing / 2))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout { content }
    }
}

/// A `Label` whose icon goes above its text at the accessibility sizes (see `AdaptiveStack`).
public struct AdaptiveLabel<Title: View, Icon: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let title: Title
    private let icon: Icon

    public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {
        self.title = title()
        self.icon = icon()
    }

    public var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                icon
                title
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        } else {
            Label { title } icon: { icon }
        }
    }
}

extension AdaptiveLabel where Title == Text, Icon == Image {
    public init(_ title: String, systemImage: String) {
        self.init { Text(title) } icon: { Image(systemName: systemImage) }
    }
}
