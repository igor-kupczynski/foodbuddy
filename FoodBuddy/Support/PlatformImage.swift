import Foundation

#if canImport(UIKit)
import UIKit

typealias PlatformImage = UIImage
typealias PlatformColor = UIColor

extension PlatformImage {
    static func fromFoodBuddyData(_ data: Data) -> PlatformImage? {
        UIImage(data: data)
    }

    func foodBuddyJPEGData(compressionQuality: CGFloat) -> Data? {
        jpegData(compressionQuality: compressionQuality)
    }
}
#elseif canImport(AppKit)
import AppKit

typealias PlatformImage = NSImage
typealias PlatformColor = NSColor

extension PlatformImage {
    static func fromFoodBuddyData(_ data: Data) -> PlatformImage? {
        NSImage(data: data)
    }

    func foodBuddyJPEGData(compressionQuality: CGFloat) -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: compressionQuality]
        )
    }
}
#endif
