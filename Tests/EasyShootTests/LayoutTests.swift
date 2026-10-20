import AppKit
import SwiftUI
import XCTest
@testable import EasyShoot

/// Hosts the real windows' SwiftUI content at small and large sizes and checks
/// that panels keep their size, stay inside the window and never overlap.
/// Set SNAPSHOT_DIR to also save a PNG of every case (CI uploads them).
@MainActor
final class LayoutTests: XCTestCase {
    private static let editorSizes: [CGSize] = [
        CGSize(width: 860, height: 520),   // the editor's minimum window size
        CGSize(width: 1024, height: 640),
        CGSize(width: 1440, height: 900),
        CGSize(width: 2560, height: 1440),
    ]
    private static let settingsSizes: [CGSize] = [
        CGSize(width: 720, height: 500),   // Settings' minimum size
        CGSize(width: 1200, height: 800),
    ]
    private let tolerance: CGFloat = 1

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "showInspector")
        super.tearDown()
    }

    // MARK: Editor

    func testEditorLayoutAtEverySize() {
        for size in Self.editorSizes {
            for tab in InspectorView.Tab.allCases {
                for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                    let name = "editor-\(Int(size.width))x\(Int(size.height))-\(tab)-\(direction == .rightToLeft ? "rtl" : "ltr")"
                    let probe = render(name: name, size: size, direction: direction) {
                        EditorView(model: self.makeModel(), presets: PresetStore.shared, inspectorTab: tab)
                    }
                    assertEditorLayout(probe, size: size, inspectorShown: true, direction: direction, name)
                }
            }
        }
    }

    func testEditorWithHiddenInspectorGivesCanvasTheWidth() {
        UserDefaults.standard.set(false, forKey: "showInspector")
        for size in Self.editorSizes {
            let name = "editor-\(Int(size.width))x\(Int(size.height))-no-inspector"
            let probe = render(name: name, size: size) {
                EditorView(model: self.makeModel(), presets: PresetStore.shared)
            }
            assertEditorLayout(probe, size: size, inspectorShown: false, direction: .leftToRight, name)
        }
    }

    func testTextBarFitsTheCanvas() {
        for size in Self.editorSizes {
            let model = makeModel()
            model.tool = .text
            let name = "editor-\(Int(size.width))x\(Int(size.height))-textbar"
            let probe = render(name: name, size: size) {
                EditorView(model: model, presets: PresetStore.shared)
            }
            guard let canvas = probe.frames["canvas"], let bar = probe.frames["textBar"] else {
                return XCTFail("\(name): canvas or text bar was not laid out")
            }
            XCTAssertGreaterThanOrEqual(bar.minX, canvas.minX - tolerance, "\(name): text bar spills left of the canvas")
            XCTAssertLessThanOrEqual(bar.maxX, canvas.maxX + tolerance, "\(name): text bar spills right of the canvas")
        }
    }

    private func assertEditorLayout(_ probe: LayoutProbe, size: CGSize, inspectorShown: Bool,
                                    direction: LayoutDirection, _ name: String) {
        let f = probe.frames
        guard let canvas = f["canvas"], let toolbar = f["toolbar"], let bottomBar = f["bottomBar"] else {
            return XCTFail("\(name): canvas, toolbar or bottom bar was not laid out")
        }
        let window = CGRect(origin: .zero, size: size)

        XCTAssertGreaterThanOrEqual(canvas.width, 400 - tolerance, "\(name): canvas is narrower than its minimum")
        XCTAssertTrue(window.insetBy(dx: -tolerance, dy: -tolerance).contains(canvas), "\(name): canvas leaves the window")
        XCTAssertEqual(bottomBar.width, size.width, accuracy: tolerance, "\(name): bottom bar doesn't span the window")
        XCTAssertGreaterThanOrEqual(toolbar.minX, canvas.minX - tolerance, "\(name): toolbar spills out of the canvas")
        XCTAssertLessThanOrEqual(toolbar.maxX, canvas.maxX + tolerance, "\(name): toolbar spills out of the canvas")

        guard inspectorShown else {
            XCTAssertNil(f["inspector"], "\(name): inspector is visible although hidden")
            XCTAssertEqual(canvas.width, size.width, accuracy: tolerance + 1, "\(name): canvas doesn't use the free width")
            return
        }
        guard let inspector = f["inspector"], let content = f["inspectorContent"], let tabs = f["inspectorTabs"] else {
            return XCTFail("\(name): inspector was not laid out")
        }
        XCTAssertEqual(inspector.width, EditorView.inspectorWidth, accuracy: tolerance, "\(name): inspector width changed")
        XCTAssertTrue(window.insetBy(dx: -tolerance, dy: -tolerance).contains(inspector), "\(name): inspector leaves the window")
        XCTAssertFalse(canvas.insetBy(dx: tolerance, dy: tolerance).intersects(inspector), "\(name): inspector overlaps the canvas")
        for (part, rect) in [("content", content), ("tabs", tabs)] {
            XCTAssertGreaterThanOrEqual(rect.minX, inspector.minX - tolerance, "\(name): inspector \(part) spills out on the leading side")
            XCTAssertLessThanOrEqual(rect.maxX, inspector.maxX + tolerance, "\(name): inspector \(part) spills out on the trailing side")
        }
        if direction == .leftToRight {
            XCTAssertGreaterThan(inspector.minX, canvas.minX, "\(name): inspector should be on the right")
        }
    }

    // MARK: Settings

    func testSettingsPagesFitTheWindow() {
        for size in Self.settingsSizes {
            for page in SettingsView.Page.allCases {
                let name = "settings-\(Int(size.width))x\(Int(size.height))-\(page.rawValue)"
                let probe = render(name: name, size: size) {
                    SettingsView(settings: .shared, presets: .shared, shortcuts: .shared, page: page)
                }
                guard let detail = probe.frames["settingsDetail"] else {
                    XCTFail("\(name): settings page was not laid out")
                    continue
                }
                let window = CGRect(origin: .zero, size: size)
                XCTAssertGreaterThan(detail.width, 300, "\(name): settings page is squeezed")
                XCTAssertLessThanOrEqual(detail.maxX, window.maxX + tolerance, "\(name): settings page leaves the window")
                if let sidebar = probe.frames["settingsSidebar"], sidebar.width > 0 {
                    XCTAssertFalse(sidebar.insetBy(dx: tolerance, dy: tolerance).intersects(detail),
                                   "\(name): sidebar overlaps the page")
                }
            }
        }
    }

    // MARK: Hosting

    private func makeModel() -> EditorModel {
        let width = 1200, height = 800
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 0.35, green: 0.3, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 80, y: 80, width: 400, height: 240))
        let model = EditorModel(result: CaptureResult(image: ctx.makeImage()!, scale: 2), preset: nil)
        model.doc.background.enabled = true
        return model
    }

    /// Puts the view in a real window at `size`, lets SwiftUI lay it out, and returns the recorded frames.
    private func render<V: View>(name: String, size: CGSize, direction: LayoutDirection = .leftToRight,
                                 @ViewBuilder content: () -> V) -> LayoutProbe {
        let probe = LayoutProbe()
        let root = content()
            .environment(\.layoutProbe, probe)
            .environment(\.layoutDirection, direction)
            .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        saveSnapshot(of: hosting, name: name)
        window.contentView = nil
        window.close()
        return probe
    }

    private func saveSnapshot(of view: NSView, name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], !dir.isEmpty,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent("\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
