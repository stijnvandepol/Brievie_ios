import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns a scanned or imported page into the JPEG that is uploaded.
public enum PageImageEncoder {
    /// Longest edge of an uploaded page, in pixels: enough to read small print, small enough to upload.
    public static let maxLongEdge = 2400
    public static let quality = 0.7

    /// The page as an upright image of at most `maxLongEdge`, for text recognition and encoding.
    ///
    /// Encoded data is decoded straight to that size (ImageIO thumbnail), so a full-size photo never sits
    /// in memory as a bitmap.
    public static func prepare(_ source: PageSource) throws(ScanError) -> CGImage {
        switch source {
        case .image(let image):
            return try scaledDown(image)
        case .encodedData(let data):
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxLongEdge
            ]
            guard
                let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
            else { throw .encodingFailed }
            return image
        }
    }

    /// `image` as JPEG, scaled down to `maxLongEdge` when it is larger. Never scaled up.
    public static func jpeg(from image: CGImage) throws(ScanError) -> Data {
        let scaled = try scaledDown(image)
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw .encodingFailed }
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, scaled, properties)
        guard CGImageDestinationFinalize(destination) else { throw .encodingFailed }
        return data as Data
    }

    private static func scaledDown(_ image: CGImage) throws(ScanError) -> CGImage {
        let longEdge = max(image.width, image.height)
        guard longEdge > maxLongEdge else { return image }
        let scale = Double(maxLongEdge) / Double(longEdge)
        let width = Int((Double(image.width) * scale).rounded())
        let height = Int((Double(image.height) * scale).rounded())
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { throw .encodingFailed }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { throw .encodingFailed }
        return scaled
    }
}
