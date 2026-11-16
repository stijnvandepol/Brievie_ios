import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The fixed palette of label colours (the server's colour keys). A key this app does not know (a later
/// palette) is grey. Each colour is a pair: a pale fill with dark text in light mode, a deep fill with pale
/// text in dark mode; the text has at least 4.5:1 against its fill in both. The values match the web's
/// `label-<key>` classes in light mode.
public enum LabelColor: String, CaseIterable, Sendable {
    case grey, blue, teal, green, yellow, orange, red, purple

    public init(key: String) {
        self = Self(rawValue: key) ?? .grey
    }

    /// The fill of a chip with this colour key.
    public static func color(forKey key: String) -> Color {
        Self(key: key).background
    }

    public var background: Color { Self.backgrounds[self] ?? .gray }
    public var foreground: Color { Self.foregrounds[self] ?? .primary }

    // Light and dark hex values per key: (light fill, dark fill) and (light text, dark text).
    private static let backgrounds: [Self: Color] = [
        .grey: dynamic(light: 0xE3E8ED, dark: 0x2E3640),
        .blue: dynamic(light: 0xDBE8F8, dark: 0x1C3456),
        .teal: dynamic(light: 0xD4EFEC, dark: 0x123F3A),
        .green: dynamic(light: 0xDCEFE3, dark: 0x17402B),
        .yellow: dynamic(light: 0xFBEFC4, dark: 0x43360A),
        .orange: dynamic(light: 0xFBE3CF, dark: 0x4A2A10),
        .red: dynamic(light: 0xFBDCDC, dark: 0x4D1C1C),
        .purple: dynamic(light: 0xE8DEF6, dark: 0x35234F)
    ]

    private static let foregrounds: [Self: Color] = [
        .grey: dynamic(light: 0x17212B, dark: 0xE3E8ED),
        .blue: dynamic(light: 0x153E75, dark: 0xC9DDF6),
        .teal: dynamic(light: 0x0F5048, dark: 0xBFE9E3),
        .green: dynamic(light: 0x14573A, dark: 0xC6E8D2),
        .yellow: dynamic(light: 0x5C4300, dark: 0xF6E3A1),
        .orange: dynamic(light: 0x7A3A06, dark: 0xF8D3B4),
        .red: dynamic(light: 0x8A1C1C, dark: 0xF8C9C9),
        .purple: dynamic(light: 0x4D2A82, dark: 0xDCCDF2)
    ]

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? uiColor(dark) : uiColor(light)
        })
        #else
        // macOS only runs the tests: the light value is enough there.
        Color(red: component(light, 16), green: component(light, 8), blue: component(light, 0))
        #endif
    }

    private static func component(_ hex: UInt32, _ shift: UInt32) -> Double {
        Double((hex >> shift) & 0xFF) / 255
    }

    #if canImport(UIKit)
    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: component(hex, 16), green: component(hex, 8), blue: component(hex, 0), alpha: 1)
    }
    #endif
}

/// A label as a small rounded rectangle with its name; the colour is a second signal, never the only one.
/// A long name wraps inside the chip instead of being cut.
public struct LabelChip: View {
    private let name: String
    private let color: LabelColor

    public init(name: String, colorKey: String) {
        self.name = name
        color = LabelColor(key: colorKey)
    }

    public var body: some View {
        Text(name)
            .font(.footnote.weight(.medium))
            .foregroundStyle(color.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.background, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

#Preview {
    ChipFlow {
        ForEach(LabelColor.allCases, id: \.self) { color in
            LabelChip(name: color.rawValue, colorKey: color.rawValue)
        }
    }
    .padding()
}
