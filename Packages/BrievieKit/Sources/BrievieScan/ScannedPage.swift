import CoreGraphics
import Foundation

/// One page of a scan, ready to upload: the JPEG and the text recognised on the device.
public struct ScannedPage: Equatable, Sendable {
    public let jpeg: Data
    /// May be empty: a blank page, or a page the recogniser could not read.
    public let text: String

    public init(jpeg: Data, text: String) {
        self.jpeg = jpeg
        self.text = text
    }
}

/// One page as it comes from the scanner or the photo library, not yet decoded at full size.
public enum PageSource: @unchecked Sendable {
    /// From the document scanner: already cropped and upright. (`CGImage` is immutable.)
    case image(CGImage)
    /// From the photo library: HEIC or JPEG bytes, with their EXIF orientation.
    case encodedData(Data)
}

public enum ScanError: Error, Equatable {
    case encodingFailed
    case recognitionFailed
}
