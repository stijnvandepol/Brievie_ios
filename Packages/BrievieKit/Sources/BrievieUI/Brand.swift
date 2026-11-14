#if os(iOS)
import SwiftUI
import UIKit

/// The brand colours, defined once. Navy in light mode; a lighter blue in dark mode that keeps at least
/// 4.5:1 against the dark grouped background. `onBrand` is the text colour on a `brand` fill.
public enum BrievieColor {
    /// Navy `#16293F` (light) / `#9DB8D6` (dark).
    public static let brand = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x9D / 255, green: 0xB8 / 255, blue: 0xD6 / 255, alpha: 1)
            : UIColor(red: 0x16 / 255, green: 0x29 / 255, blue: 0x3F / 255, alpha: 1)
    })

    /// White on navy (light); navy on the light blue (dark).
    public static let onBrand = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x16 / 255, green: 0x29 / 255, blue: 0x3F / 255, alpha: 1)
            : UIColor.white
    })
}

/// The envelope symbol and the app name on one line. `name` is passed in so each target keeps its own text.
public struct BrandMark: View {
    private let name: String

    public init(name: String) {
        self.name = name
    }

    public var body: some View {
        Label {
            Text(name)
                .font(.headline)
        } icon: {
            Image(systemName: "envelope.fill")
        }
        .foregroundStyle(BrievieColor.brand)
    }
}

#Preview {
    BrandMark(name: "Brievie")
        .padding()
}
#endif
