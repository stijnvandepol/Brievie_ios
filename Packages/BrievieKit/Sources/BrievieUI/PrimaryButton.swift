#if os(iOS)
import SwiftUI

/// The main call to action of a screen: full width, grows with Dynamic Type instead of clipping.
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
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

#Preview {
    PrimaryButton("Koppelen") {}
        .padding()
}
#endif
