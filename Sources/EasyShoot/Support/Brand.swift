import AppKit
import SwiftUI

/// EasyShoot brand palette and marks.
enum Brand {
    /// Signal orange: the one brand color, used for accents, selection and focus.
    static let signal = Color(red: 1, green: 0x5A / 255, blue: 0x1F / 255)
    static let signalNS = NSColor(srgbRed: 1, green: 0x5A / 255, blue: 0x1F / 255, alpha: 1)
    static let ink = Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x16 / 255)

    static let tagline = "Capture. Mark up. Share."
    static let taglineArabic = "التقط، وضّح، وشارك."

    /// Crop corners with a shutter dot, as a template image (adapts to light/dark menu bars).
    static func menuBarImage(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let s = rect.width / 1024
            let (x0, y0, x1, y1, l, r): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat) = (110, 110, 914, 914, 250, 70)
            let path = NSBezierPath()
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
            path.move(to: p(x0, y0 + l)); path.line(to: p(x0, y0 + r))
            path.curve(to: p(x0 + r, y0), controlPoint1: p(x0, y0), controlPoint2: p(x0, y0)); path.line(to: p(x0 + l, y0))
            path.move(to: p(x1 - l, y0)); path.line(to: p(x1 - r, y0))
            path.curve(to: p(x1, y0 + r), controlPoint1: p(x1, y0), controlPoint2: p(x1, y0)); path.line(to: p(x1, y0 + l))
            path.move(to: p(x1, y1 - l)); path.line(to: p(x1, y1 - r))
            path.curve(to: p(x1 - r, y1), controlPoint1: p(x1, y1), controlPoint2: p(x1, y1)); path.line(to: p(x1 - l, y1))
            path.move(to: p(x0 + l, y1)); path.line(to: p(x0 + r, y1))
            path.curve(to: p(x0, y1 - r), controlPoint1: p(x0, y1), controlPoint2: p(x0, y1)); path.line(to: p(x0, y1 - l))
            path.lineWidth = 110 * s
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            let dotRadius: CGFloat = 175 * s
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 512 * s - dotRadius, y: 512 * s - dotRadius,
                                        width: dotRadius * 2, height: dotRadius * 2)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "EasyShoot"
        return image
    }
}
