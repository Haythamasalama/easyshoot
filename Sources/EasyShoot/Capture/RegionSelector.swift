import AppKit

/// Full-screen overlay to drag out a rectangle. Used to choose the scrolling-capture area.
@MainActor
final class RegionSelector {
    private var windows: [NSWindow] = []
    private var completion: ((CGRect?, NSScreen?) -> Void)?
    private var screenObserver: NSObjectProtocol?

    /// Calls back with a rect in global Cocoa coordinates (bottom-left origin) and its screen, or nil if cancelled.
    func begin(message: String, completion: @escaping (CGRect?, NSScreen?) -> Void) {
        guard !NSScreen.screens.isEmpty else {
            completion(nil, nil)
            return
        }
        self.completion = completion
        // A display plugged in or out mid-selection would leave a stale screen: cancel instead.
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(nil, nil) }
        }
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
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
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
            drawLabel("\(Int(r.width)) × \(Int(r.height))", above: r)
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

    /// The size label sits above the selection, or inside it when there's no room above (dragging from the top edge).
    private func drawLabel(_ text: String, above r: CGRect) {
        let str = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
        let size = str.size()
        let boxSize = CGSize(width: size.width + 10, height: size.height + 4)
        var origin = CGPoint(x: r.minX, y: r.maxY + 6)
        if origin.y + boxSize.height > bounds.maxY { origin.y = r.maxY - boxSize.height - 6 }
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - boxSize.width - 4)
        let box = CGRect(origin: origin, size: boxSize)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        str.draw(at: CGPoint(x: box.minX + 5, y: box.minY + 2))
    }

    /// The pointer position, kept on this view's screen: the selection can't spill onto the next display.
    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
    }

    override func mouseDown(with event: NSEvent) {
        let p = point(event)
        start = p
        current = p
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = point(event)
        needsDisplay = true
    }

    /// A right-click cancels too, in case Esc can't reach the overlay.
    override func rightMouseDown(with event: NSEvent) {
        onComplete?(nil)
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
