import AppKit
import SwiftUI
import XCTest
@testable import EasyShoot

/// Drives the text tool in a real editor window, the way a person does: click, type, click away.
@MainActor
final class TextEditingTests: XCTestCase {
    private var window: NSWindow?

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    override func tearDown() {
        window?.contentView = nil
        window?.close()
        window = nil
        super.tearDown()
    }

    func testTypingIntoANewText() throws {
        let model = makeModel()
        model.tool = .text
        let canvas = try openEditor(model, size: CGSize(width: 1024, height: 640))

        click(canvas, at: CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY))
        // SwiftUI now shows the selection in the inspector and updates the bars; the text field must survive that.
        settle()
        let editor = try XCTUnwrap(openTextField(in: canvas),
                                   "the click should leave a text field open (first responder: \(describe(window?.firstResponder)))")
        XCTAssertTrue(window?.firstResponder === editor, "the text field should have the keyboard, not \(describe(window?.firstResponder))")

        // H and ش (the A key on an Arabic keyboard) are also tool letters: they must type, not switch tools.
        press("H", keyCode: 4)
        press("i", keyCode: 34)
        press(" ", keyCode: 49)
        press("ش", keyCode: 0)
        settle()
        XCTAssertEqual(model.tool, .text, "typing switched the tool")
        XCTAssertNotNil(openTextField(in: canvas), "the text field closed while typing")

        model.commitPendingEdits?()
        let texts = model.doc.annotations.filter { $0.kind == .text }
        XCTAssertEqual(texts.map(\.text), ["Hi ش"])
    }

    func testTextStaysOpenAndInPlaceWhenTheWindowResizes() throws {
        let model = makeModel()
        model.tool = .text
        let canvas = try openEditor(model, size: CGSize(width: 1024, height: 640))
        click(canvas, at: CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY))
        settle()
        let start = try XCTUnwrap(model.doc.annotations.first?.start, "the click should add a text")

        window?.setContentSize(CGSize(width: 1440, height: 900))
        settle()
        XCTAssertNotNil(openTextField(in: canvas), "resizing the window closed the text field")
        press("O", keyCode: 31)
        press("K", keyCode: 40)
        model.commitPendingEdits?()

        let text = try XCTUnwrap(model.doc.annotations.first)
        XCTAssertEqual(text.text, "OK")
        XCTAssertEqual(text.start.x, start.x, accuracy: 0.5, "the text moved on the image")
        XCTAssertEqual(text.start.y, start.y, accuracy: 0.5, "the text moved on the image")
    }

    // MARK: Helpers

    private func makeModel() -> EditorModel {
        let ctx = CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
        return EditorModel(result: CaptureResult(image: ctx.makeImage()!, scale: 2), preset: nil)
    }

    /// The editor as EditorWindowController builds it, without the app's saved settings.
    private func openEditor(_ model: EditorModel, size: CGSize) throws -> CanvasView {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EditorView(model: model, presets: PresetStore.shared))
        model.window = window
        self.window = window
        window.makeKeyAndOrderFront(nil)
        settle()
        return try XCTUnwrap(find(CanvasView.self, in: window.contentView), "no canvas in the editor")
    }

    private func settle() {
        window?.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        window?.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = find(type, in: subview) { return match }
        }
        return nil
    }

    private func openTextField(in canvas: CanvasView) -> NSTextView? {
        canvas.subviews.compactMap { $0 as? NSTextView }.first
    }

    private func describe(_ responder: NSResponder?) -> String {
        responder.map { String(describing: type(of: $0)) } ?? "none"
    }

    /// A click straight on the canvas, at a point in its own coordinates.
    private func click(_ canvas: CanvasView, at point: CGPoint) {
        guard let window else { return }
        let location = canvas.convert(point, to: nil)
        for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: kind, location: location, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                 clickCount: 1, pressure: kind == .leftMouseDown ? 1 : 0) else { continue }
            if kind == .leftMouseDown { canvas.mouseDown(with: event) } else { canvas.mouseUp(with: event) }
        }
    }

    /// A key press sent to the window, which hands it to whatever has the keyboard.
    private func press(_ characters: String, keyCode: UInt16) {
        guard let window else { return }
        for kind in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: kind, location: .zero, modifierFlags: [],
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil,
                                               characters: characters, charactersIgnoringModifiers: characters,
                                               isARepeat: false, keyCode: keyCode) else { continue }
            window.sendEvent(event)
        }
    }
}
