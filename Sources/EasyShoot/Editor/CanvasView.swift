import AppKit
import SwiftUI

struct CanvasRepresentable: NSViewRepresentable {
    @ObservedObject var model: EditorModel

    func makeNSView(context: Context) -> CanvasView {
        let view = CanvasView()
        view.model = model
        model.commitPendingEdits = { [weak view] in view?.endTextEditing() }
        return view
    }

    func updateNSView(_ view: CanvasView, context: Context) {
        view.model = model
        view.modelDidChange()
    }
}

/// The editing surface. Coordinates: view points → canvas pixels (zoom) → image pixels (layout).
final class CanvasView: NSView, NSTextViewDelegate {
    var model: EditorModel!

    private enum Drag {
        case none
        case creating(Annotation)
        case moving(id: UUID, last: CGPoint, didMove: Bool)
        case handle(id: UUID, isStart: Bool)
        case cropNew(origin: CGPoint)
        case cropMove(last: CGPoint)
        case cropResize(anchor: CGPoint)
    }

    private var drag: Drag = .none

    // Text editing state
    private var textView: NSTextView?
    private var editingID: UUID?
    private var editLeftX: CGFloat = 0
    private var editRightX: CGFloat = 0
    private var editTopY: CGFloat = 0
    private var editAppliedStyle: AnnotationStyle?
    private var editWasRTL = false

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    func modelDidChange() {
        needsDisplay = true
        guard let id = editingID else { return }
        Task { @MainActor [weak self] in
            guard let self, self.editingID == id else { return }
            if self.model.tool != .text && self.model.tool != .select {
                self.endTextEditing()
            } else if let a = self.model.annotation(id) {
                if a.style != self.editAppliedStyle { self.applyEditorAttributes(force: true) }
            } else {
                self.cancelTextEditing()
            }
        }
    }

    // MARK: Geometry

    private var layout: CanvasLayout {
        Renderer.layout(for: model.doc, showBackground: !model.isCropping, ignoreCrop: model.isCropping)
    }

    private var zoom: CGFloat {
        let size = layout.canvasSize
        guard size.width > 0, size.height > 0 else { return 1 }
        let availW = max(bounds.width - 48, 40)
        let availH = max(bounds.height - 48, 40)
        let fit = min(availW / size.width, availH / size.height)
        return min(fit, 1 / model.doc.scale)
    }

    private var canvasOrigin: CGPoint {
        let size = layout.canvasSize
        let z = zoom
        return CGPoint(x: ((bounds.width - size.width * z) / 2).rounded(), y: ((bounds.height - size.height * z) / 2).rounded())
    }

    private func imagePoint(fromView p: CGPoint) -> CGPoint {
        let o = canvasOrigin, z = zoom
        return layout.canvasToImage(CGPoint(x: (p.x - o.x) / z, y: (p.y - o.y) / z))
    }

    private func viewPoint(fromImage p: CGPoint) -> CGPoint {
        let c = layout.imageToCanvas(p)
        let o = canvasOrigin, z = zoom
        return CGPoint(x: c.x * z + o.x, y: c.y * z + o.y)
    }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        imagePoint(fromView: convert(event.locationInWindow, from: nil))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if editingID != nil {
            Task { @MainActor [weak self] in self?.endTextEditing() }
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, model != nil else { return }
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()

        let layout = self.layout
        let z = zoom, o = canvasOrigin
        ctx.saveGState()
        ctx.translateBy(x: o.x, y: o.y)
        ctx.scaleBy(x: z, y: z)

        drawCheckerboard(ctx, size: layout.canvasSize, zoom: z)

        var options = RenderOptions()
        options.drawBackground = !model.isCropping
        options.hiddenAnnotationID = editingID
        if case .creating(let a) = drag { options.draft = a }
        let needsPixelated = model.needsPixelated || options.draft?.kind == .pixelate
        Renderer.draw(model.doc, in: ctx, layout: layout, options: options, pixelated: needsPixelated ? model.pixelated : nil)

        if model.isCropping {
            drawCropOverlay(ctx, layout: layout, zoom: z)
        } else if editingID == nil, let selected = model.selectedAnnotation {
            ctx.translateBy(x: layout.imageOrigin.x, y: layout.imageOrigin.y)
            drawSelection(selected, ctx: ctx, zoom: z)
        }
        ctx.restoreGState()
    }

    private func drawCheckerboard(_ ctx: CGContext, size: CGSize, zoom: CGFloat) {
        let rect = CGRect(origin: .zero, size: size)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(rect)
        let cell = 8 / zoom
        let cols = Int(ceil(size.width / cell)), rows = Int(ceil(size.height / cell))
        guard cols * rows < 200_000 else { return }
        let path = CGMutablePath()
        for row in 0..<rows {
            for col in 0..<cols where (row + col) % 2 == 0 {
                path.addRect(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell).intersection(rect))
            }
        }
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
        ctx.fillPath()
    }

    private func drawSelection(_ a: Annotation, ctx: CGContext, zoom z: CGFloat) {
        let s = model.doc.scale
        let lineWidth = 1 / z
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        if a.kind.hasEndpointHandles {
            for p in [a.start, a.end] { drawHandle(at: p, ctx: ctx, zoom: z) }
            if a.kind == .arrow || a.kind == .line {
                ctx.restoreGState()
                return
            }
        }
        let r = Renderer.bounds(of: a, scale: s).insetBy(dx: -4 / z, dy: -4 / z)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineDash(phase: 0, lengths: [4 / z, 3 / z])
        ctx.stroke(r)
        ctx.restoreGState()
    }

    private func drawHandle(at p: CGPoint, ctx: CGContext, zoom z: CGFloat) {
        let r = 5 / z
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1.5 / z)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.strokeEllipse(in: rect)
    }

    private func drawCropOverlay(_ ctx: CGContext, layout: CanvasLayout, zoom z: CGFloat) {
        let full = CGRect(origin: .zero, size: layout.canvasSize)
        let crop = model.cropDraft.standardized
        ctx.saveGState()
        ctx.addRect(full)
        ctx.addRect(crop)
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.55))
        ctx.fillPath(using: .evenOdd)

        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.5))
        ctx.setLineWidth(1 / z)
        for i in 1...2 {
            let x = crop.minX + crop.width * CGFloat(i) / 3
            let y = crop.minY + crop.height * CGFloat(i) / 3
            ctx.move(to: CGPoint(x: x, y: crop.minY)); ctx.addLine(to: CGPoint(x: x, y: crop.maxY))
            ctx.move(to: CGPoint(x: crop.minX, y: y)); ctx.addLine(to: CGPoint(x: crop.maxX, y: y))
        }
        ctx.strokePath()

        ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
        ctx.setLineWidth(2 / z)
        ctx.stroke(crop)

        let h = 7 / z
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        for c in corners(of: crop) {
            ctx.fill(CGRect(x: c.x - h, y: c.y - h, width: h * 2, height: h * 2))
        }

        let label = "\(Int(crop.width)) × \(Int(crop.height))"
        let str = NSAttributedString(string: label, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12 / z, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
        let size = str.size()
        let labelRect = CGRect(x: crop.minX, y: max(0, crop.minY - size.height - 8 / z), width: size.width + 10 / z, height: size.height + 4 / z)
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.7))
        ctx.fill(labelRect)
        Renderer.withNSContext(ctx) {
            str.draw(at: CGPoint(x: labelRect.minX + 5 / z, y: labelRect.minY + 2 / z))
        }
        ctx.restoreGState()
    }

    private func corners(of r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        if editingID != nil {
            endTextEditing()
            return
        }
        window?.makeFirstResponder(self)
        let p = imagePoint(event)
        let s = model.doc.scale

        switch model.tool {
        case .crop:
            beginCropDrag(at: p)
        case .select:
            selectDown(at: p, event: event)
        case .text:
            if let id = Renderer.hitTest(p, in: model.doc.annotations, scale: s), model.annotation(id)?.kind == .text {
                model.selectedID = id
                beginTextEditing(id)
            } else {
                createText(at: p)
            }
        case .counter:
            if grabSelected(at: p) { break }
            var a = Annotation(kind: .counter, start: p, end: p, style: model.style)
            a.number = model.nextCounterNumber
            model.add(a)
        default:
            if grabSelected(at: p) { break }
            guard let kind = model.tool.kind else { return }
            var a = Annotation(kind: kind, start: p, end: p, style: model.style)
            if kind == .pen { a.points = [p] }
            drag = .creating(a)
        }
        needsDisplay = true
    }

    /// Lets drawing tools adjust the annotation that was just drawn (handles or body).
    private func grabSelected(at p: CGPoint) -> Bool {
        guard let selected = model.selectedAnnotation else { return false }
        if let isStart = handleHit(selected, at: p) {
            model.registerUndo()
            drag = .handle(id: selected.id, isStart: isStart)
            return true
        }
        if Renderer.hitTest(p, in: [selected], scale: model.doc.scale) != nil {
            drag = .moving(id: selected.id, last: p, didMove: false)
            return true
        }
        model.selectedID = nil
        return false
    }

    private func selectDown(at p: CGPoint, event: NSEvent) {
        if let selected = model.selectedAnnotation, let isStart = handleHit(selected, at: p) {
            model.registerUndo()
            drag = .handle(id: selected.id, isStart: isStart)
            return
        }
        if let id = Renderer.hitTest(p, in: model.doc.annotations, scale: model.doc.scale) {
            model.selectedID = id
            if event.clickCount == 2, model.annotation(id)?.kind == .text {
                beginTextEditing(id)
                return
            }
            drag = .moving(id: id, last: p, didMove: false)
        } else {
            model.selectedID = nil
        }
    }

    private func handleHit(_ a: Annotation, at p: CGPoint) -> Bool? {
        guard a.kind.hasEndpointHandles else { return nil }
        let tol = 9 / zoom
        if hypot(p.x - a.start.x, p.y - a.start.y) <= tol { return true }
        if hypot(p.x - a.end.x, p.y - a.end.y) <= tol { return false }
        return nil
    }

    private func beginCropDrag(at p: CGPoint) {
        let r = model.cropDraft.standardized
        let tol = 14 / zoom
        let cs = corners(of: r)
        for (i, c) in cs.enumerated() where hypot(p.x - c.x, p.y - c.y) <= tol {
            drag = .cropResize(anchor: cs[3 - i])
            return
        }
        if r.contains(p) {
            drag = .cropMove(last: p)
        } else {
            drag = .cropNew(origin: clampToImage(p))
        }
    }

    private func clampToImage(_ p: CGPoint) -> CGPoint {
        let size = model.doc.imageSize
        return CGPoint(x: min(max(p.x, 0), size.width), y: min(max(p.y, 0), size.height))
    }

    private func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    override func mouseDragged(with event: NSEvent) {
        let p = imagePoint(event)
        let shift = event.modifierFlags.contains(.shift)
        switch drag {
        case .none:
            return
        case .creating(var a):
            if a.kind == .pen {
                a.points.append(p)
                a.end = p
            } else {
                a.end = shift ? constrained(from: a.start, to: p, kind: a.kind) : p
            }
            drag = .creating(a)
        case .moving(let id, let last, let didMove):
            if !didMove { model.registerUndo() }
            let delta = CGPoint(x: p.x - last.x, y: p.y - last.y)
            model.update(id) { $0.offset(by: delta) }
            drag = .moving(id: id, last: p, didMove: true)
        case .handle(let id, let isStart):
            model.update(id) { a in
                let other = isStart ? a.end : a.start
                let point = shift ? constrained(from: other, to: p, kind: a.kind) : p
                if isStart { a.start = point } else { a.end = point }
            }
        case .cropNew(let origin):
            model.cropDraft = rect(origin, clampToImage(p))
        case .cropMove(let last):
            var r = model.cropDraft.standardized
            let size = model.doc.imageSize
            r.origin.x = min(max(r.origin.x + p.x - last.x, 0), size.width - r.width)
            r.origin.y = min(max(r.origin.y + p.y - last.y, 0), size.height - r.height)
            model.cropDraft = r
            drag = .cropMove(last: p)
        case .cropResize(let anchor):
            model.cropDraft = rect(anchor, clampToImage(p))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if case .creating(let a) = drag {
            let minLength = 4 / zoom
            let valid: Bool
            switch a.kind {
            case .pen: valid = a.points.count > 1
            case .arrow, .line: valid = hypot(a.end.x - a.start.x, a.end.y - a.start.y) > minLength
            default: valid = a.rect.width > minLength && a.rect.height > minLength
            }
            if valid { model.add(a) }
        }
        drag = .none
        needsDisplay = true
    }

    private func constrained(from s: CGPoint, to p: CGPoint, kind: AnnotationKind) -> CGPoint {
        let dx = p.x - s.x, dy = p.y - s.y
        switch kind {
        case .arrow, .line:
            let step = CGFloat.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step
            let len = hypot(dx, dy)
            return CGPoint(x: s.x + cos(angle) * len, y: s.y + sin(angle) * len)
        default:
            let m = max(abs(dx), abs(dy))
            return CGPoint(x: s.x + (dx < 0 ? -m : m), y: s.y + (dy < 0 ? -m : m))
        }
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 51, 117: // delete, forward delete
            model.deleteSelected()
            return
        case 53: // escape
            if model.isCropping { model.cancelCrop() } else { model.selectedID = nil }
            return
        case 36, 76: // return, enter
            if model.isCropping {
                model.applyCrop()
            } else if let a = model.selectedAnnotation, a.kind == .text {
                beginTextEditing(a.id)
            }
            return
        case 123, 124, 125, 126: // arrows
            nudge(keyCode: event.keyCode, big: flags.contains(.shift))
            return
        default:
            break
        }
        if let c = event.charactersIgnoringModifiers?.lowercased().first, let tool = Tool.forShortcut(c) {
            model.tool = tool
            return
        }
        super.keyDown(with: event)
    }

    private func nudge(keyCode: UInt16, big: Bool) {
        guard let id = model.selectedID else { return }
        let step = (big ? 10 : 1) * model.doc.scale
        var d = CGPoint.zero
        switch keyCode {
        case 123: d.x = -step
        case 124: d.x = step
        case 125: d.y = step
        default: d.y = -step
        }
        model.registerUndo()
        model.update(id) { $0.offset(by: d) }
    }

    @objc func undo(_ sender: Any?) { model.undo() }
    @objc func redo(_ sender: Any?) { model.redo() }
    @objc func delete(_ sender: Any?) { model.deleteSelected() }
    @objc func copy(_ sender: Any?) { model.copyToClipboard() }

    // MARK: Text editing

    private func createText(at p: CGPoint) {
        let s = model.doc.scale
        let pad = Renderer.textPadding(model.style, scale: s)
        let lineHalf = model.style.fontSize * s * 0.6
        let a = Annotation(kind: .text, start: CGPoint(x: p.x - pad.width, y: p.y - lineHalf - pad.height),
                           end: p, style: model.style)
        model.add(a)
        let click = viewPoint(fromImage: p)
        beginTextEditing(a.id, anchorX: click.x, isNew: true)
    }

    /// `anchorX`: for new text, the click point; the text grows rightward (LTR) or leftward (RTL) from it.
    private func beginTextEditing(_ id: UUID, anchorX: CGFloat? = nil, isNew: Bool = false) {
        guard let a = model.annotation(id) else { return }
        if editingID != nil { endTextEditing() }
        if !isNew { model.registerUndo() }
        model.selectedID = id
        editingID = id

        let s = model.doc.scale, z = zoom
        let pad = Renderer.textPadding(a.style, scale: s)
        let size = Renderer.textSize(a, scale: s)
        let topLeft = viewPoint(fromImage: CGPoint(x: a.start.x + pad.width, y: a.start.y + pad.height))
        editTopY = topLeft.y
        if let anchorX {
            editLeftX = anchorX
            editRightX = anchorX
        } else {
            editLeftX = topLeft.x
            editRightX = topLeft.x + size.width * z
        }

        let tv = NSTextView(frame: CGRect(x: topLeft.x, y: topLeft.y, width: 20, height: 20))
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.focusRingType = .none
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = true
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.delegate = self
        tv.string = a.text
        addSubview(tv)
        textView = tv
        applyEditorAttributes(force: true)
        window?.makeFirstResponder(tv)
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        needsDisplay = true
    }

    private func editorAttributes(for a: Annotation, text: String) -> [NSAttributedString.Key: Any] {
        Renderer.textAttributes(style: a.style, text: text.isEmpty ? " " : text,
                                fontSize: a.style.fontSize * model.doc.scale * zoom)
    }

    private func applyEditorAttributes(force: Bool) {
        guard let tv = textView, let id = editingID, let a = model.annotation(id) else { return }
        let rtl = a.style.textDirection.isRTL(for: tv.string)
        if force || rtl != editWasRTL {
            let attrs = editorAttributes(for: a, text: tv.string)
            tv.typingAttributes = attrs
            if let storage = tv.textStorage, storage.length > 0 {
                storage.setAttributes(attrs, range: NSRange(location: 0, length: storage.length))
            }
            if let para = attrs[.paragraphStyle] as? NSParagraphStyle {
                tv.alignment = para.alignment
                tv.baseWritingDirection = para.baseWritingDirection
            }
            tv.insertionPointColor = (attrs[.foregroundColor] as? NSColor) ?? .labelColor
            if a.style.textStyle == .background {
                tv.drawsBackground = true
                tv.backgroundColor = a.style.color.nsColor
            } else {
                tv.drawsBackground = false
            }
            editAppliedStyle = a.style
            editWasRTL = rtl
        }
        resizeTextView()
    }

    private func resizeTextView() {
        guard let tv = textView, let id = editingID, let a = model.annotation(id) else { return }
        let attrs = editorAttributes(for: a, text: tv.string)
        var measured = tv.string
        if measured.isEmpty || measured.hasSuffix("\n") { measured += " " }
        let size = Renderer.measure(NSAttributedString(string: measured, attributes: attrs))
        let fontSize = a.style.fontSize * model.doc.scale * zoom
        let width = size.width + max(4, fontSize * 0.3)
        let rtl = a.style.textDirection.isRTL(for: tv.string)
        let x = rtl ? editRightX - width : editLeftX
        tv.frame = CGRect(x: x, y: editTopY, width: width, height: max(size.height, fontSize * 1.2))
    }

    func endTextEditing() {
        guard let tv = textView, let id = editingID else { return }
        let text = tv.string
        textView = nil
        editingID = nil
        editAppliedStyle = nil
        tv.delegate = nil
        tv.removeFromSuperview()
        window?.makeFirstResponder(self)

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.discard(id)
        } else if var a = model.annotation(id) {
            a.text = text
            let s = model.doc.scale, z = zoom
            let size = Renderer.textSize(a, scale: s)
            let pad = Renderer.textPadding(a.style, scale: s)
            let rtl = a.style.textDirection.isRTL(for: text)
            let leftX = rtl ? editRightX - size.width * z : editLeftX
            let topLeft = imagePoint(fromView: CGPoint(x: leftX, y: editTopY))
            model.update(id) {
                $0.text = text
                $0.start = CGPoint(x: topLeft.x - pad.width, y: topLeft.y - pad.height)
            }
        }
        needsDisplay = true
    }

    private func cancelTextEditing() {
        textView?.delegate = nil
        textView?.removeFromSuperview()
        textView = nil
        editingID = nil
        editAppliedStyle = nil
        needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        applyEditorAttributes(force: false)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            endTextEditing()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)),
           NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            endTextEditing()
            return true
        }
        return false
    }
}
