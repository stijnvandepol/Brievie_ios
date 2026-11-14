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

/// The brand mark without its square: an envelope whose flap is a tick. Drawn in the 1024-point design
/// space of the app icon; the tick is punched out of the envelope, so the surface shows through, and its
/// tail outside the envelope is filled with the brand colour.
struct BrandGlyph: View {
    /// Design-space bounds of the mark (the tick's round caps included).
    private static let bounds = CGRect(x: 156, y: 228, width: 712, height: 568)
    static let aspectRatio = bounds.width / bounds.height

    private static let envelope = Path(
        roundedRect: CGRect(x: 156, y: 396, width: 600, height: 400), cornerSize: CGSize(width: 52, height: 52)
    )
    private static let tick: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 232, y: 472))
        path.addLine(to: CGPoint(x: 456, y: 664))
        path.addLine(to: CGPoint(x: 836, y: 260))
        return path
    }()
    private static let stroke = StrokeStyle(lineWidth: 64, lineCap: .round, lineJoin: .round)

    var body: some View {
        Canvas { context, size in
            let scale = size.height / Self.bounds.height
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -Self.bounds.minX, y: -Self.bounds.minY)
            let brand = GraphicsContext.Shading.color(BrievieColor.brand)
            context.drawLayer { layer in
                layer.fill(Self.envelope, with: brand)
                layer.blendMode = .destinationOut
                layer.stroke(Self.tick, with: .color(.black), style: Self.stroke)
            }
            context.drawLayer { layer in
                layer.stroke(Self.tick, with: brand, style: Self.stroke)
                layer.blendMode = .destinationOut
                layer.fill(Self.envelope, with: .color(.black))
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The brand mark and the app name on one line. `name` is passed in so each target keeps its own text.
public struct BrandMark: View {
    private let name: String
    /// Roughly the cap height of the headline text times 1.6; follows Dynamic Type.
    @ScaledMetric(relativeTo: .headline) private var glyphHeight: CGFloat = 28

    public init(name: String) {
        self.name = name
    }

    public var body: some View {
        HStack(spacing: 8) {
            BrandGlyph()
                .frame(height: glyphHeight)
            Text(name)
                .font(.headline)
                .foregroundStyle(BrievieColor.brand)
        }
    }
}

#Preview {
    BrandMark(name: "Brievie")
        .padding()
}
#endif
