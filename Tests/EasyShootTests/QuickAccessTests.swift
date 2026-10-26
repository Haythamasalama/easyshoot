import AppKit
import SwiftUI
import XCTest
@testable import EasyShoot

@MainActor
final class QuickAccessTests: XCTestCase {
    /// A very wide or very tall screenshot (a scrolling capture) is cropped to the thumbnail. If it sized the
    /// thumbnail instead, the content grew past the panel and the close and edit buttons ended up outside it.
    func testThumbnailFitsItsPanelWhateverTheScreenshotShape() {
        for (width, height) in [(4000, 300), (300, 6000), (1600, 1000), (500, 500)] {
            let image = makeImage(width: width, height: height)
            let panel = QuickAccessPanel(result: CaptureResult(image: image, scale: 2), manager: QuickAccessManager.shared)
            let size = panel.frame.size
            panel.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(panel.frame.size, size, "\(width)×\(height): the thumbnail resized its panel")

            // At its own ideal size the thumbnail is exactly the panel, so the corner buttons sit inside it.
            let view = QuickAccessView(image: NSImage(cgImage: image, size: CGSize(width: width, height: height)), size: size,
                                       onHover: { _ in }, onCopy: {}, onSave: {}, onEdit: {}, onClose: {},
                                       dragProvider: { NSItemProvider() })
            let fitting = NSHostingView(rootView: view).fittingSize
            XCTAssertEqual(fitting.width, size.width, accuracy: 0.5, "\(width)×\(height): thumbnail is wider than its panel")
            XCTAssertEqual(fitting.height, size.height, accuracy: 0.5, "\(width)×\(height): thumbnail is taller than its panel")
            panel.close()
        }
    }

    private func makeImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }
}
