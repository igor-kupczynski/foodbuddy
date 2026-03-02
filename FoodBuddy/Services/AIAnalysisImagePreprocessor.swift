import Foundation
import CoreGraphics

struct AIAnalysisProcessedImage: Sendable, Equatable {
    let jpegData: Data
    let pixelSize: CGSize
}

struct AIAnalysisImagePreprocessor {
    let maxLongEdge: CGFloat
    let compressionQuality: CGFloat

    init(
        maxLongEdge: CGFloat,
        compressionQuality: CGFloat
    ) {
        self.maxLongEdge = maxLongEdge
        self.compressionQuality = compressionQuality
    }

    func preprocessForAI(_ imageData: Data) -> AIAnalysisProcessedImage {
        guard let image = PlatformImage.fromFoodBuddyData(imageData) else {
            return AIAnalysisProcessedImage(
                jpegData: imageData,
                pixelSize: .zero
            )
        }

        let resized = image.foodBuddyResized(maxLongEdge: maxLongEdge)
        guard let jpegData = resized.foodBuddyJPEGData(compressionQuality: compressionQuality) else {
            return AIAnalysisProcessedImage(
                jpegData: imageData,
                pixelSize: image.foodBuddyPixelSize
            )
        }

        return AIAnalysisProcessedImage(
            jpegData: jpegData,
            pixelSize: resized.foodBuddyPixelSize
        )
    }
}
