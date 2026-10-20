import AppKit

/// Full-screen overlay to drag out a rectangle. Used to choose the scrolling-capture area.
@MainActor
final class RegionSelector {
    private var windows: [NSWindow] = []
    private var completion: ((CGRect?, NSScreen?) -> Void)?

    /// Calls back with a rect in global Cocoa coordinates (bottom-left origin) and its screen, or nil if cancelled.
    func begin(message: String, completion: @escaping (CGRect?, NSScreen?) -> Void) {
        self.completion = completion
        for screen in NSScreen.screens {
            let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.setFrame(screen.frame, display: false)

            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.message = message
            view.onComplete = { [weak self] rect in
                guard let self else { return }
                if let rect {
                    let global = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY).integral
                    self.finish(global, screen)
                } else {
                    self.finish(nil, nil)
                }
            }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            windows.append(window)
        }
        NSApp.activate()
        let mouse = NSEvent.mouseLocation
        if let window = windows.first(where: { $0.frame.contains(mouse) }) {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(window.contentView)
        }
    }

    private func finish(_ rect: CGRect?, _ screen: NSScreen?) {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        let callback = completion
        completion = nil
        callback?(rect, screen)
    }
}

private final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SelectionView: NSView {
    var onComplete: ((CGRect?) -> Void)?
    var message = ""
    private var start: CGPoint?
    private var current: CGPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var selection: CGRect? {
        guard let s = start, let c = current else { return nil }
        return CGRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(c.x - s.x), height: abs(c.y - s.y))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        if let r = selection {
            NSColor.clear.setFill()
            r.fill(using: .copy)
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: r.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1
            border.stroke()
            drawLabel("\(Int(r.width)) × \(Int(r.height))", at: CGPoint(x: r.minX, y: r.maxY + 6))
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
            let str = NSAttributedString(string: message, attributes: attrs)
            let size = str.size()
            let box = CGRect(x: bounds.midX - size.width / 2 - 16, y: bounds.midY - size.height / 2 - 10,
                             width: size.width + 32, height: size.height + 20)
            NSColor.black.withAlphaComponent(0.6).setFill()
            NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
            str.draw(at: CGPoint(x: box.minX + 16, y: box.minY + 10))
        }
    }

    private func drawLabel(_ text: String, at point: CGPoint) {
        let str = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
        let size = str.size()
        let box = CGRect(x: point.x, y: point.y, width: size.width + 10, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        str.draw(at: CGPoint(x: box.minX + 5, y: box.minY + 2))
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        start = p
        current = p
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let r = selection, r.width >= 40, r.height >= 40 {
            onComplete?(r)
        } else {
            start = nil
            current = nil
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onComplete?(nil) } else { super.keyDown(with: event) }
    }
}
