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
        guard let image = storedPixels(ofJPEG: data) else { return nil }
        return (image.width, image.height)
    }

    /// The bitmap as stored in the file, without applying any EXIF orientation: what a viewer that ignores
    /// EXIF (or a file without it) shows.
    static func storedPixels(ofJPEG data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// The EXIF orientation written in the file; `nil` when there is none.
    static func orientationTag(ofJPEG data: Data) -> Int? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        return properties[kCGImagePropertyOrientation] as? Int
    }

    enum Corner: Equatable, CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    /// A white page (portrait unless `width > height`) with one black square near `corner`, as seen on screen.
    static func marked(width: Int = 300, height: Int = 400, corner: Corner = .topLeft) -> CGImage {
        let context = bitmap(width: width, height: height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let side = min(width, height) / 5
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        // Core Graphics counts y from the bottom.
        let rect = CGRect(
            x: left ? side / 2 : width - side * 3 / 2, y: top ? height - side * 3 / 2 : side / 2,
            width: side, height: side
        )
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(rect)
        guard let image = context.makeImage() else { fatalError("Cannot make an image") }
        return image
    }

    /// The corner whose quarter holds the dark pixels of `image`, as seen on screen (row 0 at the top).
    static func darkCorner(of image: CGImage) -> Corner? {
        let width = image.width
        let height = image.height
        let context = bitmap(width: width, height: height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
        var sumX = 0
        var sumY = 0
        var count = 0
        for row in 0..<height {
            for column in 0..<width where bytes[row * context.bytesPerRow + column * 4] < 80 {
                sumX += column
                sumY += row
                count += 1
            }
        }
        guard count > 0 else { return nil }
        let left = sumX / count < width / 2
        let top = sumY / count < height / 2
        switch (top, left) {
        case (true, true): return .topLeft
        case (true, false): return .topRight
        case (false, true): return .bottomLeft
        case (false, false): return .bottomRight
        }
    }

    static func bitmap(width: Int, height: Int) -> CGContext {
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { fatalError("Cannot create a bitmap context") }
        return context
    }
}
