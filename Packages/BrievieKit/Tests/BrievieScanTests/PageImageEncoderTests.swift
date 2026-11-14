import BrievieScan
import Foundation
import Testing

@Suite struct PageImageEncoderTests {
    @Test func largeImageIsScaledDownAndEncodedAsASmallJPEG() throws {
        let jpeg = try PageImageEncoder.jpeg(from: TestImages.page(width: 4000, height: 3000, blocks: true))

        #expect(jpeg.prefix(3) == Data([0xFF, 0xD8, 0xFF]))
        let size = try #require(TestImages.size(ofJPEG: jpeg))
        #expect(size.width == 2400)
        #expect(size.height == 1800)
        #expect(jpeg.count < 1_500_000)
    }

    @Test func smallImageIsNotScaledUp() throws {
        let jpeg = try PageImageEncoder.jpeg(from: TestImages.page(width: 1000, height: 800))

        let size = try #require(TestImages.size(ofJPEG: jpeg))
        #expect(size.width == 1000)
        #expect(size.height == 800)
    }

    @Test func preparedScannerImageIsScaledDown() throws {
        let image = try PageImageEncoder.prepare(.image(TestImages.page(width: 3000, height: 4000)))

        #expect(image.width == 1800)
        #expect(image.height == 2400)
    }

    @Test func encodedPhotoIsTurnedUprightAndScaledDown() throws {
        // A photo taken in portrait is stored as a landscape bitmap with EXIF orientation 6.
        let stored = TestImages.page(width: 4000, height: 3000)
        let data = TestImages.jpegData(stored, orientation: 6)

        let image = try PageImageEncoder.prepare(.encodedData(data))

        #expect(image.width == 1800)
        #expect(image.height == 2400)
    }

    @Test func dataThatIsNotAnImageIsRefused() {
        #expect(throws: ScanError.encodingFailed) {
            try PageImageEncoder.prepare(.encodedData(Data("geen afbeelding".utf8)))
        }
    }
}
