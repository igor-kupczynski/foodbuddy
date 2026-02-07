import Foundation
import CoreGraphics

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

    var foodBuddyPixelSize: CGSize {
        size
    }

    func foodBuddyResized(maxLongEdge: CGFloat) -> PlatformImage {
        guard maxLongEdge > 0 else {
            return self
        }

        let original = foodBuddyPixelSize
        let longEdge = max(original.width, original.height)
        guard longEdge > maxLongEdge else {
            return self
        }

        let scale = maxLongEdge / longEdge
        let targetSize = CGSize(
            width: max(1, floor(original.width * scale)),
            height: max(1, floor(original.height * scale))
        )

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
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

    var foodBuddyPixelSize: CGSize {
        CGSize(width: size.width, height: size.height)
    }

    func foodBuddyResized(maxLongEdge: CGFloat) -> PlatformImage {
        guard maxLongEdge > 0 else {
            return self
        }

        let original = foodBuddyPixelSize
        let longEdge = max(original.width, original.height)
        guard longEdge > maxLongEdge else {
            return self
        }

        let scale = maxLongEdge / longEdge
        let targetSize = CGSize(
            width: max(1, floor(original.width * scale)),
            height: max(1, floor(original.height * scale))
        )

        let resized = NSImage(size: NSSize(width: targetSize.width, height: targetSize.height))
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: original),
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()
        return resized
    }
}
#endif
