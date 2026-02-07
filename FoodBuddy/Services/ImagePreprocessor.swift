import CoreGraphics
import Foundation

struct ProcessedImage {
    let fullJPEGData: Data
    let thumbnailJPEGData: Data
    let fullPixelSize: CGSize
    let thumbnailPixelSize: CGSize
}

struct ImagePreprocessor {
    enum Error: Swift.Error {
        case fullEncodingFailed
        case thumbnailEncodingFailed
    }

    let maxFullLongEdge: CGFloat
    let maxThumbnailLongEdge: CGFloat
    let fullCompressionQuality: CGFloat
    let thumbnailCompressionQuality: CGFloat

    init(
        maxFullLongEdge: CGFloat = 1600,
        maxThumbnailLongEdge: CGFloat = 320,
        fullCompressionQuality: CGFloat = 0.75,
        thumbnailCompressionQuality: CGFloat = 0.65
    ) {
        self.maxFullLongEdge = maxFullLongEdge
        self.maxThumbnailLongEdge = maxThumbnailLongEdge
        self.fullCompressionQuality = fullCompressionQuality
        self.thumbnailCompressionQuality = thumbnailCompressionQuality
    }

    func preprocess(_ image: PlatformImage) throws -> ProcessedImage {
        let fullImage = image.foodBuddyResized(maxLongEdge: maxFullLongEdge)
        let thumbnailImage = fullImage.foodBuddyResized(maxLongEdge: maxThumbnailLongEdge)

        guard let fullJPEGData = fullImage.foodBuddyJPEGData(compressionQuality: fullCompressionQuality) else {
            throw Error.fullEncodingFailed
        }

        guard let thumbnailJPEGData = thumbnailImage.foodBuddyJPEGData(
            compressionQuality: thumbnailCompressionQuality
        ) else {
            throw Error.thumbnailEncodingFailed
        }

        return ProcessedImage(
            fullJPEGData: fullJPEGData,
            thumbnailJPEGData: thumbnailJPEGData,
            fullPixelSize: fullImage.foodBuddyPixelSize,
            thumbnailPixelSize: thumbnailImage.foodBuddyPixelSize
        )
    }
}
