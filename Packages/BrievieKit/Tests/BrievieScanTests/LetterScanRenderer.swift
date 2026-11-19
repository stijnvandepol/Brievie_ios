import BrievieScan
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// How a phone scan spoils a printed page. Everything is deterministic: the same style gives the same pixels.
struct ScanStyle: Sendable, CustomStringConvertible {
    var font = "Helvetica"
    /// Degrees counter-clockwise: a crop that was not quite straight.
    var skew = 0.0
    /// Scaled down to this share and back up again: a soft focus. 1 is sharp.
    var softness = 1.0
    /// Grey ink on grey paper instead of black on white.
    var lowContrast = false
    /// A shadow over one side of the page, as from a hand or the phone.
    var shadow = false
    /// Light speckles, from a fixed seed.
    var noise = false

    var description: String {
        var parts = [font]
        if skew != 0 { parts.append("skew \(skew)°") }
        if softness < 1 { parts.append("blur") }
        if lowContrast { parts.append("low contrast") }
        if shadow { parts.append("shadow") }
        if noise { parts.append("noise") }
        return parts.joined(separator: ", ")
    }
}

/// Draws a letter's text on an A4 page (150 dpi) and spoils it like a phone scan.
enum LetterScanRenderer {
    static let width = 1240
    static let height = 1754

    /// The page as the scanner would hand it over: JPEG bytes, turned by `turn`.
    static func scan(_ text: String, style: ScanStyle, turn: QuarterTurn) throws -> Data {
        var page = render(text, style: style)
        if style.softness < 1 { page = soften(page, by: style.softness) }
        if style.shadow { page = shadow(page) }
        if style.noise { page = speckle(page) }
        page = try PageImageEncoder.rotated(page, by: turn)
        return jpeg(page, quality: 0.8)
    }

    private static func render(_ text: String, style: ScanStyle) -> CGImage {
        let context = TestImages.bitmap(width: width, height: height)
        let paper = style.lowContrast ? 0.86 : 1
        let ink = style.lowContrast ? 0.42 : 0.05
        context.setFillColor(CGColor(gray: paper, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // The skew turns the text around the middle of the page; the corners show paper.
        context.translateBy(x: Double(width) / 2, y: Double(height) / 2)
        context.rotate(by: style.skew * .pi / 180)
        context.translateBy(x: -Double(width) / 2, y: -Double(height) / 2)

        let font = CTFontCreateWithName(style.font as CFString, 22, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: ink, alpha: 1)
        ]
        let framesetter = CTFramesetterCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes)
        )
        let box = CGRect(x: 110, y: 110, width: width - 220, height: height - 260)
        let frame = CTFramesetterCreateFrame(
            framesetter, CFRange(location: 0, length: 0), CGPath(rect: box, transform: nil), nil
        )
        CTFrameDraw(frame, context)
        guard let image = context.makeImage() else { fatalError("Cannot render the letter") }
        return image
    }

    private static func soften(_ image: CGImage, by share: Double) -> CGImage {
        let small = TestImages.bitmap(
            width: Int(Double(image.width) * share), height: Int(Double(image.height) * share)
        )
        small.interpolationQuality = .medium
        small.draw(image, in: CGRect(x: 0, y: 0, width: small.width, height: small.height))
        guard let reduced = small.makeImage() else { fatalError("Cannot soften") }
        let full = TestImages.bitmap(width: image.width, height: image.height)
        full.interpolationQuality = .medium
        full.draw(reduced, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let softened = full.makeImage() else { fatalError("Cannot soften") }
        return softened
    }

    /// Darkens the page from its right edge (55% of the light) to clear at the middle.
    private static func shadow(_ image: CGImage) -> CGImage {
        let context = TestImages.bitmap(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.45)] as CFArray,
                locations: [0, 1]
            )
        else { fatalError("Cannot make the shadow") }
        context.drawLinearGradient(
            gradient, start: CGPoint(x: image.width / 2, y: image.height / 3),
            end: CGPoint(x: image.width, y: 0), options: [.drawsAfterEndLocation]
        )
        guard let shaded = context.makeImage() else { fatalError("Cannot make the shadow") }
        return shaded
    }

    /// Small grey dots at places a fixed linear congruential generator picks.
    private static func speckle(_ image: CGImage) -> CGImage {
        let context = TestImages.bitmap(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var seed: UInt64 = 20_261_119
        func next() -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(seed >> 33)
        }
        for _ in 0..<4000 {
            let gray = Double(next() % 100) / 100
            context.setFillColor(CGColor(gray: gray, alpha: 0.5))
            context.fill(CGRect(x: next() % image.width, y: next() % image.height, width: 2, height: 2))
        }
        guard let speckled = context.makeImage() else { fatalError("Cannot add noise") }
        return speckled
    }

    private static func jpeg(_ image: CGImage, quality: Double) -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { fatalError("Cannot create a JPEG destination") }
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
