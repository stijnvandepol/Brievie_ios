import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TestImages {
    /// A white page with a few dark blocks, like a scanned letter.
    static func page(width: Int, height: Int, blocks: Bool = false) -> CGImage {
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { fatalError("Cannot create a bitmap context") }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if blocks {
            context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
            for row in 0..<40 {
                let top = height / 12 + row * height / 50
                context.fill(CGRect(x: width / 10, y: top, width: width * 7 / 10, height: 6))
            }
        }
        guard let image = context.makeImage() else { fatalError("Cannot make an image") }
        return image
    }

    /// JPEG bytes of `image` tagged with an EXIF orientation (6 = rotated 90° clockwise to display).
    static func jpegData(_ image: CGImage, orientation: Int) -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { fatalError("Cannot create a JPEG destination") }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func size(ofJPEG data: Data) -> (width: Int, height: Int)? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return (image.width, image.height)
    }
}
