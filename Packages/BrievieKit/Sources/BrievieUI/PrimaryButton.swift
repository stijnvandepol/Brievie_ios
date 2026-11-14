#if os(iOS)
import SwiftUI

/// Rounded-rectangle button look shared by `PrimaryButton` and `SecondaryButton`: full width, at least 50pt
/// high, grows with Dynamic Type. The system styles draw a capsule on iOS 26 whatever the border shape, so the
/// shape is drawn here; disabled and pressed states are handled below.
private struct BrievieButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(foreground)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // Brand fill with its own text colour (white would fail in dark mode); a disabled button turns grey but
    // keeps secondary-label text, which stays readable in light and dark mode.
    private var foreground: Color {
        guard isEnabled else { return Color(.secondaryLabel) }
        return kind == .primary ? BrievieColor.onBrand : BrievieColor.brand
    }

    private var background: Color {
        guard isEnabled else { return Color(.tertiarySystemFill) }
        return kind == .primary ? BrievieColor.brand : BrievieColor.brand.opacity(0.14)
    }
}

/// The main call to action of a screen.
public struct PrimaryButton: View {
    private let title: String
    private let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(title, action: action)
            .buttonStyle(BrievieButtonStyle(kind: .primary))
    }
}

/// The secondary action under a `PrimaryButton`.
public struct SecondaryButton: View {
    private let title: String
    private let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(title, action: action)
            .buttonStyle(BrievieButtonStyle(kind: .secondary))
    }
}

#Preview {
    VStack {
        PrimaryButton("Scan QR-code") {}
        PrimaryButton("Scan QR-code") {}.disabled(true)
        SecondaryButton("Plak koppelgegevens") {}
    }
    .padding()
}
#endif
