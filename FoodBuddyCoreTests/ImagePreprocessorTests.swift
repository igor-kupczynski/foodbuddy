import CoreGraphics
import ImageIO
import XCTest

final class ImagePreprocessorTests: XCTestCase {
    func testPreprocessConstrainsLongEdgeAndGeneratesThumbnail() throws {
        let preprocessor = ImagePreprocessor(
            maxFullLongEdge: 1600,
            maxThumbnailLongEdge: 320,
            fullCompressionQuality: 0.75,
            thumbnailCompressionQuality: 0.65
        )

        let source = TestImageFactory.make(color: .systemBlue, width: 4000, height: 2000)
        let processed = try preprocessor.preprocess(source)

        XCTAssertLessThanOrEqual(max(processed.fullPixelSize.width, processed.fullPixelSize.height), 1600)
        XCTAssertLessThanOrEqual(max(processed.thumbnailPixelSize.width, processed.thumbnailPixelSize.height), 320)

        XCTAssertNotNil(PlatformImage.fromFoodBuddyData(processed.fullJPEGData))
        XCTAssertNotNil(PlatformImage.fromFoodBuddyData(processed.thumbnailJPEGData))
        XCTAssertLessThan(processed.thumbnailJPEGData.count, processed.fullJPEGData.count)
    }

    func testPreprocessProducesJPEGDataEnvelope() throws {
        let preprocessor = ImagePreprocessor()
        let source = TestImageFactory.make(color: .systemGreen, width: 2400, height: 1800)

        let processed = try preprocessor.preprocess(source)

        XCTAssertTrue(processed.fullJPEGData.count > 0)
        XCTAssertTrue(processed.thumbnailJPEGData.count > 0)
        XCTAssertEqual(jpegUTType(for: processed.fullJPEGData), "public.jpeg")
        XCTAssertEqual(jpegUTType(for: processed.thumbnailJPEGData), "public.jpeg")
    }

    private func jpegUTType(for data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else {
            return nil
        }

        return type as String
    }
}
