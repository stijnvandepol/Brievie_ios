// Generates the placeholder app icon: a white envelope on a deep-blue square.
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

// Background #1F3A5F.
context.setFillColor(CGColor(colorSpace: colorSpace, components: [31 / 255, 58 / 255, 95 / 255, 1]) ?? .black)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))

// Envelope body, centred with a generous margin.
let width: CGFloat = 560
let height: CGFloat = 400
let body = CGRect(x: (CGFloat(size) - width) / 2, y: (CGFloat(size) - height) / 2, width: width, height: height)
let white = CGColor(colorSpace: colorSpace, components: [1, 1, 1, 1]) ?? .white
let blue = CGColor(colorSpace: colorSpace, components: [31 / 255, 58 / 255, 95 / 255, 1]) ?? .black

context.setFillColor(white)
context.addPath(CGPath(roundedRect: body, cornerWidth: 36, cornerHeight: 36, transform: nil))
context.fillPath()

// Flap: a "V" in the background colour from the top corners to the centre.
context.setStrokeColor(blue)
context.setLineWidth(28)
context.setLineCap(.round)
context.setLineJoin(.round)
context.move(to: CGPoint(x: body.minX + 44, y: body.maxY - 48))
context.addLine(to: CGPoint(x: body.midX, y: body.midY + 20))
context.addLine(to: CGPoint(x: body.maxX - 44, y: body.maxY - 48))
context.strokePath()

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
