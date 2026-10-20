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
        // The inspector is a system column that may live in its own hosting view, so compare
        // sizes rather than positions across the canvas and the inspector.
        let range = EditorView.inspectorWidthRange
        XCTAssertGreaterThanOrEqual(inspector.width, range.lowerBound - tolerance, "\(name): inspector is \(inspector.width) pt, narrower than its minimum")
        XCTAssertLessThanOrEqual(inspector.width, range.upperBound + tolerance, "\(name): inspector is \(inspector.width) pt, wider than its maximum")
        XCTAssertLessThanOrEqual(canvas.width + inspector.width, size.width + tolerance + 1, "\(name): inspector overlaps the canvas")
        for (part, rect) in [("content", content), ("tabs", tabs)] {
            XCTAssertGreaterThanOrEqual(rect.minX, inspector.minX - tolerance, "\(name): inspector \(part) spills out on the leading side")
            XCTAssertLessThanOrEqual(rect.maxX, inspector.maxX + tolerance, "\(name): inspector \(part) spills out on the trailing side")
        }
        if direction == .leftToRight {
            XCTAssertEqual(canvas.minX, 0, accuracy: tolerance, "\(name): canvas should start at the left edge, with the inspector on the right")
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

    // MARK: Real screens, 13" to 24"

    /// Default "looks like" resolutions, minus the menu bar.
    private static let screens: [(name: String, visible: CGSize)] = [
        ("13in-MacBook-Air-M1-1440x900", CGSize(width: 1440, height: 875)),
        ("13in-MacBook-Air-1470x956", CGSize(width: 1470, height: 918)),
        ("14in-MacBook-Pro-1512x982", CGSize(width: 1512, height: 944)),
        ("15in-MacBook-Air-1710x1112", CGSize(width: 1710, height: 1074)),
        ("16in-MacBook-Pro-1728x1117", CGSize(width: 1728, height: 1079)),
        ("24in-iMac-2240x1260", CGSize(width: 2240, height: 1235)),
    ]

    func testEditorOpensAtAGoodSizeOnEveryScreen() {
        for screen in Self.screens {
            let visible = CGRect(origin: .zero, size: screen.visible)
            for image in [CGSize(width: 400, height: 300), CGSize(width: 1440, height: 900), CGSize(width: 3000, height: 2000)] {
                let size = EditorWindowController.initialContentSize(imagePoints: image, visibleFrame: visible)
                XCTAssertGreaterThanOrEqual(size.width, EditorWindowController.minimumSize.width, screen.name)
                XCTAssertGreaterThanOrEqual(size.height, EditorWindowController.minimumSize.height, screen.name)
                XCTAssertLessThanOrEqual(size.width, screen.visible.width * 0.9 + 0.5, "\(screen.name): wider than the screen allows")
                XCTAssertLessThanOrEqual(size.height, screen.visible.height * 0.9 + 0.5, "\(screen.name): taller than the screen allows")
            }
        }
    }

    /// Renders every window as it opens on each screen, and the editor maximized.
    func testWindowsOnEveryScreen() {
        for screen in Self.screens {
            let visible = CGRect(origin: .zero, size: screen.visible)
            // A typical full-window capture on a Retina Mac.
            let imagePoints = CGSize(width: screen.visible.width * 0.7, height: screen.visible.height * 0.7)
            let opening = EditorWindowController.initialContentSize(imagePoints: imagePoints, visibleFrame: visible)
            for (label, size) in [("editor", opening), ("editor-maximized", screen.visible)] {
                let name = "screen-\(screen.name)-\(label)"
                let probe = render(name: name, size: size) {
                    EditorView(model: self.makeModel(points: imagePoints), presets: PresetStore.shared)
                }
                assertEditorLayout(probe, size: size, inspectorShown: true, direction: .leftToRight, name)
            }
            XCTAssertLessThanOrEqual(640, screen.visible.height, "\(screen.name): Welcome window doesn't fit")
        }
        _ = render(name: "screen-any-settings-general", size: CGSize(width: 760, height: 540)) {
            SettingsView(settings: .shared, presets: .shared, shortcuts: .shared)
        }
        _ = render(name: "screen-any-welcome", size: CGSize(width: 520, height: 640)) {
            WelcomeView(close: {})
        }
    }

    // MARK: Hosting

    private func makeModel(points: CGSize = CGSize(width: 600, height: 400)) -> EditorModel {
        let width = Int(points.width * 2), height = Int(points.height * 2)
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 0.35, green: 0.3, blue: 0.9, alpha: 1))
        // A sidebar, a header and a few cards, so the screenshots look like an app.
        ctx.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.93, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width / 5, height: height))
        ctx.setFillColor(CGColor(red: 0.35, green: 0.3, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: width / 5 + 60, y: height - 140, width: width / 3, height: 60))
        for i in 0..<3 {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: width / 5 + 60 + i * (width / 4), y: height / 3, width: width / 5, height: height / 3))
        }
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
        // ARC owns the window; letting AppKit also release it on close crashes the test run.
        window.isReleasedWhenClosed = false
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
