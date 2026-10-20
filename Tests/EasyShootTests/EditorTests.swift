import XCTest
@testable import EasyShoot

final class TextDirectionTests: XCTestCase {
    func testDetectsArabicAndHebrew() {
        XCTAssertTrue(TextDirection.detectRTL("مرحبا بالعالم"))
        XCTAssertTrue(TextDirection.detectRTL("123 اضغط هنا"))
        XCTAssertTrue(TextDirection.detectRTL("שלום"))
        XCTAssertFalse(TextDirection.detectRTL("Hello مرحبا"))
        XCTAssertFalse(TextDirection.detectRTL("Click here"))
        XCTAssertFalse(TextDirection.detectRTL(""))
    }

    func testExplicitDirectionsOverrideDetection() {
        XCTAssertTrue(TextDirection.rtl.isRTL(for: "Hello"))
        XCTAssertFalse(TextDirection.ltr.isRTL(for: "مرحبا"))
        XCTAssertTrue(TextDirection.auto.isRTL(for: "مرحبا"))
    }
}

@MainActor
final class RendererTests: XCTestCase {
    private func makeImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    func testLayoutWithoutBackgroundMatchesCrop() {
        var doc = EditorDocument(image: makeImage(width: 400, height: 300), scale: 2)
        doc.crop = CGRect(x: 50, y: 40, width: 200, height: 100)
        let layout = Renderer.layout(for: doc)
        XCTAssertEqual(layout.canvasSize, CGSize(width: 200, height: 100))
        XCTAssertEqual(layout.imageToCanvas(CGPoint(x: 50, y: 40)), .zero)
    }

    func testLayoutAddsPaddingAndAspectRatio() {
        var doc = EditorDocument(image: makeImage(width: 400, height: 300), scale: 2)
        doc.background.enabled = true
        doc.background.padding = 50 // 100 px at 2x
        doc.background.aspectRatio = .auto
        XCTAssertEqual(Renderer.layout(for: doc).canvasSize, CGSize(width: 600, height: 500))

        doc.background.aspectRatio = .sixteenNine
        let layout = Renderer.layout(for: doc)
        XCTAssertEqual(layout.canvasSize.width / layout.canvasSize.height, 16.0 / 9.0, accuracy: 0.01)
        XCTAssertEqual(layout.contentRect.midX, layout.canvasSize.width / 2, accuracy: 1)
    }

    func testRenderAppliesExportFactor() {
        var doc = EditorDocument(image: makeImage(width: 400, height: 300), scale: 2)
        doc.annotations.append(Annotation(kind: .arrow, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 200, y: 150), style: AnnotationStyle()))
        var text = Annotation(kind: .text, start: CGPoint(x: 20, y: 200), end: .zero, style: AnnotationStyle())
        text.text = "مرحبا Hello"
        doc.annotations.append(text)
        let image = Renderer.renderImage(doc, factor: 0.5, pixelated: nil, opaque: false)
        XCTAssertEqual(image?.width, 200)
        XCTAssertEqual(image?.height, 150)
    }

    func testHitTestFindsArrow() {
        let arrow = Annotation(kind: .arrow, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), style: AnnotationStyle())
        XCTAssertEqual(Renderer.hitTest(CGPoint(x: 50, y: 51), in: [arrow], scale: 1), arrow.id)
        XCTAssertNil(Renderer.hitTest(CGPoint(x: 90, y: 10), in: [arrow], scale: 1))
    }
}
