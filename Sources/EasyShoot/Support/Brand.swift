import AppKit
import SwiftUI

/// EasyShoot brand palette and marks.
enum Brand {
    /// Signal orange: the one brand color, used for accents, selection and focus.
    static let signal = Color(red: 1, green: 0x5A / 255, blue: 0x1F / 255)
    static let signalNS = NSColor(srgbRed: 1, green: 0x5A / 255, blue: 0x1F / 255, alpha: 1)
    /// Graphite: the icon body and dark surfaces.
    static let graphite = Color(red: 0x0F / 255, green: 0x0F / 255, blue: 0x12 / 255)
    static let graphiteLight = Color(red: 0x2E / 255, green: 0x2E / 255, blue: 0x35 / 255)
    /// Paper: light text on graphite.
    static let paper = Color(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF6 / 255)

    static let tagline = "Capture. Mark up. Share."
    static let taglineArabic = "التقط، وضّح، وشارك."

    /// The app icon. Outside an app bundle (tests, `swift run`) macOS would show a generic folder,
    /// so draw the same mark as Branding/AppIcon.svg instead.
    @MainActor static var appIcon: NSImage {
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") != nil { return NSApp.applicationIconImage }
        return NSImage(size: NSSize(width: 256, height: 256), flipped: true) { rect in
            let s = rect.width / 1024
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
            let body = NSBezierPath(roundedRect: CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                                    xRadius: 185 * s, yRadius: 185 * s)
            NSGradient(starting: NSColor(srgbRed: 0x0F / 255, green: 0x0F / 255, blue: 0x12 / 255, alpha: 1),
                       ending: NSColor(srgbRed: 0x2E / 255, green: 0x2E / 255, blue: 0x35 / 255, alpha: 1))?
                .draw(in: body, angle: -90)
            let corners = NSBezierPath()
            for (start, corner, end) in [((300, 428), (300, 300), (428, 300)), ((596, 300), (724, 300), (724, 428)),
                                         ((724, 596), (724, 724), (596, 724)), ((428, 724), (300, 724), (300, 596))] {
                let c = p(CGFloat(corner.0), CGFloat(corner.1))
                corners.move(to: p(CGFloat(start.0), CGFloat(start.1)))
                corners.curve(to: p(CGFloat(end.0), CGFloat(end.1)), controlPoint1: c, controlPoint2: c)
            }
            corners.lineWidth = 58 * s
            corners.lineCapStyle = .round
            signalNS.setStroke()
            corners.stroke()
            let cross = NSBezierPath()
            cross.move(to: p(512, 436)); cross.line(to: p(512, 588))
            cross.move(to: p(436, 512)); cross.line(to: p(588, 512))
            cross.lineWidth = 28 * s
            cross.lineCapStyle = .round
            NSColor(srgbRed: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF6 / 255, alpha: 1).setStroke()
            cross.stroke()
            return true
        }
    }

    /// Selection corners around a crosshair (Branding/MenuBarMark.svg), as a template image (adapts to light/dark menu bars).
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
            let cross = NSBezierPath()
            cross.move(to: p(512, 370)); cross.line(to: p(512, 654))
            cross.move(to: p(370, 512)); cross.line(to: p(654, 512))
            cross.lineWidth = 84 * s
            cross.lineCapStyle = .round
            cross.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "EasyShoot"
        return image
    }
}
