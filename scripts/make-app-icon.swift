// Generates the app icon: a white envelope whose flap is a tick, on a navy square.
// Usage (from the repo root): swift scripts/make-app-icon.swift
// The PNG is opaque (no alpha channel, sRGB) and has square corners, as App Store Connect requires.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let output = "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
          data: nil,
          width: size,
          height: size,
          bitsPerComponent: 8,
          bytesPerRow: 0,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      )
else {
    fatalError("Cannot create the drawing context")
}

// Work in the SVG design space: origin top-left, y down.
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: 1, y: -1)

let navy = CGColor(colorSpace: colorSpace, components: [0x16 / 255, 0x29 / 255, 0x3F / 255, 1]) ?? .black
let white = CGColor(colorSpace: colorSpace, components: [1, 1, 1, 1]) ?? .white

context.setFillColor(navy)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

let envelope = CGPath(
    roundedRect: CGRect(x: 156, y: 396, width: 600, height: 400),
    cornerWidth: 52, cornerHeight: 52, transform: nil
)
let tick = CGMutablePath()
tick.move(to: CGPoint(x: 232, y: 472))
tick.addLine(to: CGPoint(x: 456, y: 664))
tick.addLine(to: CGPoint(x: 836, y: 260))

func strokeTick(_ colour: CGColor) {
    context.setStrokeColor(colour)
    context.setLineWidth(64)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(tick)
    context.strokePath()
}

// The flap is a tick whose tail runs past the envelope: white outside, navy inside.
strokeTick(white)
context.setFillColor(white)
context.addPath(envelope)
context.fillPath()
context.saveGState()
context.addPath(envelope)
context.clip()
strokeTick(navy)
context.restoreGState()

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil
      )
else {
    fatalError("Cannot create the image destination")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Cannot write \(output)")
}
print("Wrote \(output)")
