import BrievieScan
import CoreGraphics
import Foundation
import Testing
#if canImport(UIKit)
import UIKit
#endif

/// Follows a page through every hop to the uploaded bytes (source → `prepare` → `jpeg`) and checks that what
/// the server stores shows the page as the phone showed it: upright pixels, no EXIF orientation left to apply.
/// The server and the web show the bytes as they are, and the page hash is taken over those bytes.
@Suite struct OrientationChainTests {
    /// Where the stored bitmap's top-left corner appears on screen, per EXIF orientation (1...8).
    static let displayedCorner: [Int: TestImages.Corner] = [
        1: .topLeft, 2: .topRight, 3: .bottomRight, 4: .bottomLeft,
        5: .topLeft, 6: .topRight, 7: .bottomRight, 8: .bottomLeft
    ]

    @Test(arguments: 1...8)
    func photoWithEXIFOrientationIsUploadedWithUprightPixels(orientation: Int) throws {
        // Stored landscape with the mark top-left; orientations 5...8 turn it into a portrait page.
        let stored = TestImages.marked(width: 400, height: 300, corner: .topLeft)
        let data = TestImages.jpegData(stored, orientation: orientation)

        let jpeg = try PageImageEncoder.jpeg(from: PageImageEncoder.prepare(.encodedData(data)))

        let pixels = try #require(TestImages.storedPixels(ofJPEG: jpeg))
        #expect(TestImages.darkCorner(of: pixels) == Self.displayedCorner[orientation])
        #expect(pixels.width == (orientation >= 5 ? 300 : 400))
        #expect(TestImages.orientationTag(ofJPEG: jpeg) ?? 1 == 1)
    }

    @Test(arguments: TestImages.Corner.allCases)
    func scannerImageKeepsItsPixelsAsTheyAre(corner: TestImages.Corner) throws {
        let jpeg = try PageImageEncoder.jpeg(
            from: PageImageEncoder.prepare(.image(TestImages.marked(width: 3000, height: 4000, corner: corner)))
        )

        let pixels = try #require(TestImages.storedPixels(ofJPEG: jpeg))
        #expect(TestImages.darkCorner(of: pixels) == corner)
        #expect(pixels.width == 1800)
    }

    #if canImport(UIKit)
    /// The scanner hands over `UIImage.jpegData` of `VNDocumentCameraScan.imageOfPage(at:)`. Whatever
    /// `imageOrientation` that image has, the uploaded pixels show it as the `UIImage` showed it.
    @Test(arguments: [
        (UIImage.Orientation.up, 1), (.upMirrored, 2), (.down, 3), (.downMirrored, 4),
        (.leftMirrored, 5), (.right, 6), (.rightMirrored, 7), (.left, 8)
    ])
    func scannerUIImageWithAnyOrientationIsUploadedAsShown(orientation: UIImage.Orientation, exif: Int) throws {
        let stored = TestImages.marked(width: 400, height: 300, corner: .topLeft)
        let shown = UIImage(cgImage: stored, scale: 1, orientation: orientation)
        let data = try #require(shown.jpegData(compressionQuality: 0.9))

        let jpeg = try PageImageEncoder.jpeg(from: PageImageEncoder.prepare(.encodedData(data)))

        let pixels = try #require(TestImages.storedPixels(ofJPEG: jpeg))
        #expect(TestImages.darkCorner(of: pixels) == Self.displayedCorner[exif])
        #expect(CGFloat(pixels.width) == shown.size.width)
        #expect(TestImages.orientationTag(ofJPEG: jpeg) ?? 1 == 1)
    }
    #endif

    @Test func markHelperFindsTheCornerItDrew() {
        for corner in TestImages.Corner.allCases {
            #expect(TestImages.darkCorner(of: TestImages.marked(corner: corner)) == corner)
        }
    }
}
