import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum TestImageFactory {
    static func make(color: PlatformColor) -> PlatformImage {
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        #elseif canImport(AppKit)
        let image = NSImage(size: NSSize(width: 24, height: 24))
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 24, height: 24)).fill()
        image.unlockFocus()
        return image
        #endif
    }
}
