#if os(iOS)
import SwiftUI

/// The main call to action of a screen: full width, at least 50pt high, grows with Dynamic Type instead
/// of clipping.
public struct PrimaryButton: View {
    private let title: String
    private let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(BrievieColor.onBrand)
                .frame(maxWidth: .infinity, minHeight: 50)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.borderedProminent)
        .tint(BrievieColor.brand)
    }
}

/// The secondary action under a `PrimaryButton`: bordered, same height.
public struct SecondaryButton: View {
    private let title: String
    private let action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered)
        .tint(BrievieColor.brand)
    }
}

#Preview {
    VStack {
        PrimaryButton("Scan QR-code") {}
        SecondaryButton("Plak koppelgegevens") {}
    }
    .padding()
}
#endif
