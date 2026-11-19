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

    /// `image` as JPEG, scaled down to `maxLongEdge` when it is larger. Never scaled up. The file carries no
    /// EXIF orientation: its pixels are upright, because the server and the web show the bytes as they are.
    public static func jpeg(from image: CGImage) throws(ScanError) -> Data {
        try encode(scaledDown(image, to: maxLongEdge), quality: quality)
    }

    /// A small JPEG of the page for the preview before saving: the same pixels as the upload, cheap to show.
    public static func preview(of image: CGImage) throws(ScanError) -> Data {
        try encode(scaledDown(image, to: previewLongEdge), quality: quality)
    }

    /// Longest edge of the preview, in pixels.
    public static let previewLongEdge = 640

    /// `image` turned by `turn`, clockwise as seen on screen.
    public static func rotated(_ image: CGImage, by turn: QuarterTurn) throws(ScanError) -> CGImage {
        guard turn != .upright else { return image }
        let width = turn.swapsSides ? image.height : image.width
        let height = turn.swapsSides ? image.width : image.height
        let context = try bitmap(width: width, height: height)
        // Core Graphics turns counter-clockwise for positive angles (y up).
        context.translateBy(x: Double(width) / 2, y: Double(height) / 2)
        context.rotate(by: -Double(turn.rawValue) * .pi / 2)
        context.draw(
            image,
            in: CGRect(
                x: -Double(image.width) / 2, y: -Double(image.height) / 2,
                width: Double(image.width), height: Double(image.height)
            )
        )
        guard let turned = context.makeImage() else { throw .encodingFailed }
        return turned
    }

    private static func encode(_ image: CGImage, quality: Double) throws(ScanError) -> Data {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw .encodingFailed }
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw .encodingFailed }
        return data as Data
    }

    private static func scaledDown(
        _ image: CGImage, to longEdgeLimit: Int = maxLongEdge
    ) throws(ScanError) -> CGImage {
        let longEdge = max(image.width, image.height)
        guard longEdge > longEdgeLimit else { return image }
        let scale = Double(longEdgeLimit) / Double(longEdge)
        let width = Int((Double(image.width) * scale).rounded())
        let height = Int((Double(image.height) * scale).rounded())
        let context = try bitmap(width: width, height: height)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { throw .encodingFailed }
        return scaled
    }

    private static func bitmap(width: Int, height: Int) throws(ScanError) -> CGContext {
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else { throw .encodingFailed }
        return context
    }
}
