// Draws the test letter used by VisionTextRecognizerTests.
// Run from this directory: swift make-letter.swift
import AppKit

let size = CGSize(width: 1240, height: 1754)  // A4 at 150 dpi
let lines = [
    "Belastingdienst",
    "",
    "Datum 3 november 2026",
    "",
    "Geachte heer, mevrouw,",
    "U moet € 1.234,56 betalen vóór 1 december 2026."
]

guard
    let space = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(
        data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ),
    let font = NSFont(name: "Helvetica", size: 34)
else { fatalError("Cannot set up drawing") }
context.setFillColor(.white)
context.fill(CGRect(origin: .zero, size: size))

NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
for (index, line) in lines.enumerated() {
    let point = CGPoint(x: 120, y: size.height - 220 - CGFloat(index) * 60)
    (line as NSString).draw(at: point, withAttributes: attributes)
}

let url = URL(fileURLWithPath: "letter-nl.png")
guard
    let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
else { fatalError("Cannot write the image") }
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("wrote \(url.path)")
