import AppKit
import CoreImage

/// Where the screenshot sits on the output canvas.
struct CanvasLayout {
    var canvasSize: CGSize
    /// Rect of the (cropped) screenshot on the canvas.
    var contentRect: CGRect
    /// Visible part of the source image, in image pixels.
    var crop: CGRect

    /// Canvas position of image pixel (0, 0).
    var imageOrigin: CGPoint {
        CGPoint(x: contentRect.minX - crop.minX, y: contentRect.minY - crop.minY)
    }

    func imageToCanvas(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x + imageOrigin.x, y: p.y + imageOrigin.y)
    }

    func canvasToImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - imageOrigin.x, y: p.y - imageOrigin.y)
    }
}

struct RenderOptions {
    var drawBackground = true
    var hiddenAnnotationID: UUID?
    var draft: Annotation?
}

/// Draws an `EditorDocument` into a top-left-origin (flipped) CGContext.
/// The same code paints the editor canvas and the exported image, so what you see is what you get.
@MainActor
enum Renderer {

    // MARK: Layout

    static func layout(for doc: EditorDocument, showBackground: Bool = true, ignoreCrop: Bool = false) -> CanvasLayout {
        let crop = ignoreCrop ? doc.fullRect : doc.crop
        let bg = doc.background
        guard showBackground, bg.enabled else {
            return CanvasLayout(canvasSize: crop.size, contentRect: CGRect(origin: .zero, size: crop.size), crop: crop)
        }
        let p = bg.padding * doc.scale
        var w = crop.width + 2 * p
        var h = crop.height + 2 * p
        if let ratio = bg.aspectRatio.value {
            if w / h < ratio { w = h * ratio } else { h = w / ratio }
        }
        w = w.rounded(.up)
        h = h.rounded(.up)
        let freeX = w - crop.width - 2 * p
        let freeY = h - crop.height - 2 * p
        let a = bg.alignment.unit
        let rect = CGRect(x: (p + freeX * a.x).rounded(), y: (p + freeY * a.y).rounded(),
                          width: crop.width, height: crop.height)
        return CanvasLayout(canvasSize: CGSize(width: w, height: h), contentRect: rect, crop: crop)
    }

    // MARK: Full render

    static func renderImage(_ doc: EditorDocument, factor: CGFloat = 1, pixelated: CGImage?, opaque: Bool) -> CGImage? {
        let layout = Self.layout(for: doc)
        let w = max(1, Int((layout.canvasSize.width * factor).rounded()))
        let h = max(1, Int((layout.canvasSize.height * factor).rounded()))
        var space = CGColorSpace(name: CGColorSpace.sRGB)!
        if let cs = doc.image.colorSpace, cs.model == .rgb, cs.supportsOutput { space = cs }
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.scaleBy(x: CGFloat(w) / layout.canvasSize.width, y: CGFloat(h) / layout.canvasSize.height)
        ctx.interpolationQuality = .high
        if opaque {
            ctx.setFillColor(.white)
            ctx.fill(CGRect(origin: .zero, size: layout.canvasSize))
        }
        draw(doc, in: ctx, layout: layout, options: RenderOptions(), pixelated: pixelated)
        return ctx.makeImage()
    }

    static func draw(_ doc: EditorDocument, in ctx: CGContext, layout: CanvasLayout, options: RenderOptions, pixelated: CGImage?) {
        let s = doc.scale
        let bg = doc.background
        let showBackground = options.drawBackground && bg.enabled
        let canvasRect = CGRect(origin: .zero, size: layout.canvasSize)

        if showBackground {
            drawBackgroundFill(bg, in: canvasRect, ctx)
        }

        let content = layout.contentRect
        let radius = showBackground ? min(bg.cornerRadius * s, min(content.width, content.height) / 2) : 0
        let contentPath = CGPath(roundedRect: content, cornerWidth: radius, cornerHeight: radius, transform: nil)

        if showBackground && bg.shadow > 0 && bg.shadowOpacity > 0 {
            ctx.saveGState()
            let d = deviceScale(ctx)
            ctx.setShadow(offset: CGSize(width: 0, height: -bg.shadow * s * 0.3 * d),
                          blur: bg.shadow * s * d,
                          color: CGColor(gray: 0, alpha: bg.shadowOpacity))
            ctx.addPath(contentPath)
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fillPath()
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.addPath(contentPath)
        ctx.clip()
        drawImage(doc.image, in: CGRect(origin: layout.imageOrigin, size: doc.imageSize), ctx)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.translateBy(x: layout.imageOrigin.x, y: layout.imageOrigin.y)
        var list = doc.annotations
        if let draft = options.draft { list.append(draft) }
        for a in list where a.id != options.hiddenAnnotationID {
            drawAnnotation(a, doc: doc, ctx: ctx, pixelated: pixelated, visibleRect: layout.crop)
        }
        ctx.restoreGState()
    }

    // MARK: Background

    static func drawBackgroundFill(_ bg: BackgroundSettings, in rect: CGRect, _ ctx: CGContext) {
        switch bg.fill {
        case .transparent:
            return
        case .solid:
            ctx.setFillColor(bg.solidColor.cgColor)
            ctx.fill(rect)
        case .gradient, .custom:
            let colors = bg.gradientColors.map(\.cgColor) as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: nil) else { return }
            let (start, end) = gradientPoints(in: rect, angle: bg.gradientAngle)
            ctx.saveGState()
            ctx.clip(to: rect)
            ctx.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }
    }

    /// Angle in degrees, 0 = left→right, 90 = top→bottom (y grows downward).
    static func gradientPoints(in rect: CGRect, angle: Double) -> (CGPoint, CGPoint) {
        let rad = angle * .pi / 180
        let dx = CGFloat(cos(rad)), dy = CGFloat(sin(rad))
        let half = (abs(rect.width * dx) + abs(rect.height * dy)) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        return (CGPoint(x: c.x - dx * half, y: c.y - dy * half), CGPoint(x: c.x + dx * half, y: c.y + dy * half))
    }

    // MARK: Helpers

    /// Draws a CGImage upright into a flipped (top-left origin) context.
    static func drawImage(_ image: CGImage, in rect: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    /// Shadows are specified in device space, so they need the current CTM scale.
    static func deviceScale(_ ctx: CGContext) -> CGFloat {
        let t = ctx.ctm
        return max(0.01, hypot(t.a, t.b))
    }

    static func withNSContext(_ ctx: CGContext, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func applyShadow(_ ctx: CGContext, scale s: CGFloat) {
        let d = deviceScale(ctx)
        ctx.setShadow(offset: CGSize(width: 0, height: -1 * s * d), blur: 4 * s * d, color: CGColor(gray: 0, alpha: 0.35))
    }

    // MARK: Annotations

    static func drawAnnotation(_ a: Annotation, doc: EditorDocument, ctx: CGContext, pixelated: CGImage?, visibleRect: CGRect) {
        let s = doc.scale
        let st = a.style
        let color = st.color.cgColor
        let lw = max(0.5, st.lineWidth * s)

        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let wantsShadow = st.shadow && a.kind != .highlighter && a.kind != .pixelate
        if wantsShadow { applyShadow(ctx, scale: s) }

        switch a.kind {
        case .arrow:
            if let path = arrowPath(from: a.start, to: a.end, width: lw) {
                ctx.addPath(path)
                ctx.setFillColor(color)
                ctx.fillPath()
            }
        case .line:
            ctx.move(to: a.start)
            ctx.addLine(to: a.end)
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lw)
            ctx.strokePath()
        case .rectangle:
            let r = a.rect
            let radius = min(lw, r.width / 2, r.height / 2)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lw)
            ctx.strokePath()
        case .filledRectangle:
            let r = a.rect
            let radius = min(4 * s, r.width / 2, r.height / 2)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.setFillColor(color)
            ctx.fillPath()
        case .ellipse:
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lw)
            ctx.strokeEllipse(in: a.rect)
        case .highlighter:
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(st.color.withAlpha(0.45).cgColor)
            ctx.fill(a.rect)
        case .pen:
            guard let path = smoothPath(a.points) else { return }
            ctx.addPath(path)
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lw)
            ctx.strokePath()
        case .pixelate:
            let r = a.rect.intersection(visibleRect)
            guard !r.isNull, r.width > 0, r.height > 0 else { return }
            ctx.clip(to: r)
            if let pixelated {
                drawImage(pixelated, in: CGRect(origin: .zero, size: doc.imageSize), ctx)
            } else {
                ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
                ctx.fill(r)
            }
        case .counter:
            drawCounter(a, scale: s, ctx: ctx)
        case .text:
            drawText(a, scale: s, ctx: ctx)
        }
    }

    static func arrowPath(from a: CGPoint, to b: CGPoint, width w: CGFloat) -> CGPath? {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 1 else { return nil }
        let ux = dx / len, uy = dy / len
        let px = -uy, py = ux
        let headLen = min(len * 0.7, w * 3.2 + 8)
        let headHalf = headLen * 0.55
        let base = CGPoint(x: b.x - ux * headLen, y: b.y - uy * headLen)
        let tail = w * 0.3
        let neck = w * 0.55

        let path = CGMutablePath()
        path.move(to: CGPoint(x: a.x + px * tail, y: a.y + py * tail))
        path.addLine(to: CGPoint(x: base.x + px * neck, y: base.y + py * neck))
        path.addLine(to: CGPoint(x: base.x + px * headHalf, y: base.y + py * headHalf))
        path.addLine(to: b)
        path.addLine(to: CGPoint(x: base.x - px * headHalf, y: base.y - py * headHalf))
        path.addLine(to: CGPoint(x: base.x - px * neck, y: base.y - py * neck))
        path.addLine(to: CGPoint(x: a.x - px * tail, y: a.y - py * tail))
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: a.x - tail, y: a.y - tail, width: tail * 2, height: tail * 2))
        return path
    }

    static func smoothPath(_ points: [CGPoint]) -> CGPath? {
        guard let first = points.first, points.count > 1 else { return nil }
        let path = CGMutablePath()
        path.move(to: first)
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }
        for i in 1..<points.count - 1 {
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2, y: (points[i].y + points[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    // MARK: Counter

    static func counterRadius(_ a: Annotation, scale s: CGFloat) -> CGFloat {
        max(8, a.style.fontSize * 0.7) * s
    }

    static func drawCounter(_ a: Annotation, scale s: CGFloat, ctx: CGContext) {
        let r = counterRadius(a, scale: s)
        let c = a.start
        let circle = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.setFillColor(a.style.color.cgColor)
        ctx.fillEllipse(in: circle)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        ctx.setLineWidth(max(1, r * 0.1))
        ctx.strokeEllipse(in: circle.insetBy(dx: r * 0.05, dy: r * 0.05))

        let textColor: NSColor = a.style.color.isLight ? .black : .white
        let str = NSAttributedString(string: "\(a.number)", attributes: [
            .font: NSFont.systemFont(ofSize: r * 1.05, weight: .bold),
            .foregroundColor: textColor,
        ])
        let size = str.size()
        withNSContext(ctx) {
            str.draw(at: CGPoint(x: c.x - size.width / 2, y: c.y - size.height / 2))
        }
    }

    // MARK: Text

    static func textPadding(_ style: AnnotationStyle, scale s: CGFloat) -> CGSize {
        CGSize(width: style.fontSize * 0.4 * s, height: style.fontSize * 0.2 * s)
    }

    static func textAttributes(style: AnnotationStyle, text: String, fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
        let rtl = style.textDirection.isRTL(for: text)
        let para = NSMutableParagraphStyle()
        para.baseWritingDirection = rtl ? .rightToLeft : .leftToRight
        para.alignment = rtl ? .right : .left
        let fg: NSColor
        if style.textStyle == .background {
            fg = style.color.isLight ? .black : .white
        } else {
            fg = style.color.nsColor
        }
        return [.font: style.font(size: fontSize), .foregroundColor: fg, .paragraphStyle: para]
    }

    static func measure(_ str: NSAttributedString) -> CGSize {
        let r = str.boundingRect(with: CGSize(width: 100_000, height: 100_000),
                                 options: [.usesLineFragmentOrigin, .usesFontLeading])
        return CGSize(width: ceil(r.width), height: ceil(r.height))
    }

    static func attributedText(_ a: Annotation, scale s: CGFloat) -> NSAttributedString {
        let text = a.text.isEmpty ? " " : a.text
        return NSAttributedString(string: text, attributes: textAttributes(style: a.style, text: text, fontSize: a.style.fontSize * s))
    }

    /// Text size (without padding) in image pixels.
    static func textSize(_ a: Annotation, scale s: CGFloat) -> CGSize {
        measure(attributedText(a, scale: s))
    }

    /// Full text box including padding, in image pixels. `start` is its top-left corner.
    static func textFrame(_ a: Annotation, scale s: CGFloat) -> CGRect {
        let size = textSize(a, scale: s)
        let pad = textPadding(a.style, scale: s)
        return CGRect(x: a.start.x, y: a.start.y, width: size.width + pad.width * 2, height: size.height + pad.height * 2)
    }

    static func drawText(_ a: Annotation, scale s: CGFloat, ctx: CGContext) {
        let str = attributedText(a, scale: s)
        let size = measure(str)
        let pad = textPadding(a.style, scale: s)
        let frame = CGRect(x: a.start.x, y: a.start.y, width: size.width + pad.width * 2, height: size.height + pad.height * 2)

        if a.style.textStyle == .background {
            let radius = min(frame.height / 2, a.style.fontSize * 0.45 * s)
            ctx.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.setFillColor(a.style.color.cgColor)
            ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
        }

        let textRect = CGRect(x: frame.minX + pad.width, y: frame.minY + pad.height, width: size.width, height: size.height)
        withNSContext(ctx) {
            if a.style.textStyle == .outline {
                let outline = NSMutableAttributedString(attributedString: str)
                let range = NSRange(location: 0, length: outline.length)
                outline.addAttribute(.strokeColor, value: a.style.color.isLight ? NSColor.black : NSColor.white, range: range)
                outline.addAttribute(.strokeWidth, value: 16, range: range)
                outline.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
            }
            str.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
    }

    // MARK: Hit testing

    static func bounds(of a: Annotation, scale s: CGFloat) -> CGRect {
        let lw = a.style.lineWidth * s
        switch a.kind {
        case .text:
            return textFrame(a, scale: s)
        case .counter:
            let r = counterRadius(a, scale: s)
            return CGRect(x: a.start.x - r, y: a.start.y - r, width: r * 2, height: r * 2)
        case .pen:
            guard let first = a.points.first else { return .null }
            var r = CGRect(origin: first, size: .zero)
            for p in a.points { r = r.union(CGRect(origin: p, size: .zero)) }
            return r.insetBy(dx: -lw / 2, dy: -lw / 2)
        default:
            return a.rect.insetBy(dx: -lw / 2, dy: -lw / 2)
        }
    }

    static func hitTest(_ p: CGPoint, in annotations: [Annotation], scale s: CGFloat) -> UUID? {
        for a in annotations.reversed() {
            let tol = max(a.style.lineWidth * s, 6 * s)
            switch a.kind {
            case .arrow, .line:
                if distance(p, segment: a.start, a.end) <= tol { return a.id }
            case .pen:
                for i in 0..<max(0, a.points.count - 1) where distance(p, segment: a.points[i], a.points[i + 1]) <= tol {
                    return a.id
                }
            default:
                if bounds(of: a, scale: s).insetBy(dx: -tol / 2, dy: -tol / 2).contains(p) { return a.id }
            }
        }
        return nil
    }

    static func distance(_ p: CGPoint, segment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    // MARK: Pixelate

    static func pixelate(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(max(8, 9 * scale), forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
        guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        return CIContext(options: nil).createCGImage(output, from: input.extent)
    }
}
