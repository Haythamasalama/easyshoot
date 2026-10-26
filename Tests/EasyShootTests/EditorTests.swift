import AppKit
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

    func testNewEditorStartsFromLastUsedSettings() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "EasyShootTests.lastUsed"))
        defaults.removePersistentDomain(forName: "EasyShootTests.lastUsed")
        var background = BackgroundSettings()
        background.enabled = true
        background.padding = 80
        let saved = LastUsed(background: background, style: AnnotationStyle(color: .blue),
                             export: ExportOptions(format: .jpeg), tool: Tool.text.rawValue)
        LastUsedStore.save(saved, to: defaults)

        let loaded = try XCTUnwrap(LastUsedStore.load(from: defaults))
        XCTAssertEqual(loaded, saved)

        let result = CaptureResult(image: makeImage(width: 40, height: 30), scale: 1)
        let model = EditorModel(result: result, preset: nil, lastUsed: loaded)
        XCTAssertEqual(model.doc.background, background)
        XCTAssertEqual(model.style, saved.style)
        XCTAssertEqual(model.export.format, .jpeg)
        XCTAssertEqual(model.tool, .text)

        // An explicit default preset still wins.
        let preset = Preset(name: "Plain", background: BackgroundSettings(), style: AnnotationStyle(), export: ExportOptions())
        let withPreset = EditorModel(result: result, preset: preset, lastUsed: loaded)
        XCTAssertFalse(withPreset.doc.background.enabled)
        XCTAssertEqual(withPreset.tool, .arrow)
    }
}

final class UpdaterTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(Updater.isVersion("1.0.3", newerThan: "1.0.2"))
        XCTAssertTrue(Updater.isVersion("1.10.0", newerThan: "1.9.9"))
        XCTAssertTrue(Updater.isVersion("2", newerThan: "1.9"))
        XCTAssertFalse(Updater.isVersion("1.0.2", newerThan: "1.0.2"))
        XCTAssertFalse(Updater.isVersion("1.0", newerThan: "1.0.0"))
        XCTAssertFalse(Updater.isVersion("1.0.1", newerThan: "1.0.2"))
    }
}

final class FontLookupTests: XCTestCase {
    func testFindsAFamilyInBold() throws {
        let font = try XCTUnwrap(NSFont.family("Helvetica", size: 20, bold: true))
        XCTAssertEqual(font.familyName, "Helvetica")
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertEqual(NSFont.family("Helvetica", size: 20, bold: false)?.fontDescriptor.symbolicTraits.contains(.bold), false)
    }

    /// An unknown family falls back to the system font, never to some other font that happens to match.
    func testUnknownFamilyIsNotFound() {
        XCTAssertNil(NSFont.family("No Such Family 4242", size: 20, bold: true))
        XCTAssertNil(NSFont.family("", size: 20, bold: true))
        XCTAssertEqual(AnnotationStyle(fontName: "No Such Family 4242").font(size: 20), .systemFont(ofSize: 20, weight: .semibold))
    }
}
