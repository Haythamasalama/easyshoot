import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Color

struct RGBAColor: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            Double((hex >> 16) & 0xFF) / 255,
            Double((hex >> 8) & 0xFF) / 255,
            Double(hex & 0xFF) / 255,
            alpha
        )
    }

    init(nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.sRGB) ?? .black
        self.init(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    }

    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    func withAlpha(_ alpha: Double) -> RGBAColor { RGBAColor(r, g, b, alpha) }

    /// True for colors where dark text reads better than white text.
    var isLight: Bool { (0.299 * r + 0.587 * g + 0.114 * b) > 0.65 }

    static let red = RGBAColor(hex: 0xFF3B30)
    static let orange = RGBAColor(hex: 0xFF9500)
    static let yellow = RGBAColor(hex: 0xFFCC00)
    static let green = RGBAColor(hex: 0x34C759)
    static let blue = RGBAColor(hex: 0x0A84FF)
    static let purple = RGBAColor(hex: 0xAF52DE)
    static let pink = RGBAColor(hex: 0xFF2D55)
    static let black = RGBAColor(hex: 0x111111)
    static let white = RGBAColor(hex: 0xFFFFFF)

    static let palette: [RGBAColor] = [.red, .orange, .yellow, .green, .blue, .purple, .pink, .black, .white]
}

// MARK: - Tools & annotations

enum AnnotationKind: String, Codable, CaseIterable {
    case arrow, line, rectangle, filledRectangle, ellipse, text, counter, highlighter, pen, pixelate

    /// Kinds that are defined by two draggable points.
    var hasEndpointHandles: Bool {
        switch self {
        case .arrow, .line, .rectangle, .filledRectangle, .ellipse, .highlighter, .pixelate: return true
        case .text, .counter, .pen: return false
        }
    }
}

enum Tool: String, CaseIterable, Identifiable {
    case select, crop, arrow, line, rectangle, filledRectangle, ellipse, text, counter, highlighter, pen, pixelate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: return "Select & Move"
        case .crop: return "Crop"
        case .arrow: return "Arrow"
        case .line: return "Line"
        case .rectangle: return "Rectangle"
        case .filledRectangle: return "Filled Rectangle"
        case .ellipse: return "Ellipse"
        case .text: return "Text"
        case .counter: return "Counter"
        case .highlighter: return "Highlighter"
        case .pen: return "Pen"
        case .pixelate: return "Pixelate"
        }
    }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .crop: return "crop"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .filledRectangle: return "rectangle.fill"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .counter: return "1.circle"
        case .highlighter: return "highlighter"
        case .pen: return "scribble"
        case .pixelate: return "square.grid.3x3.fill"
        }
    }

    var shortcut: Character {
        switch self {
        case .select: return "v"
        case .crop: return "c"
        case .arrow: return "a"
        case .line: return "l"
        case .rectangle: return "r"
        case .filledRectangle: return "f"
        case .ellipse: return "o"
        case .text: return "t"
        case .counter: return "n"
        case .highlighter: return "h"
        case .pen: return "p"
        case .pixelate: return "b"
        }
    }

    var kind: AnnotationKind? {
        switch self {
        case .select, .crop: return nil
        case .arrow: return .arrow
        case .line: return .line
        case .rectangle: return .rectangle
        case .filledRectangle: return .filledRectangle
        case .ellipse: return .ellipse
        case .text: return .text
        case .counter: return .counter
        case .highlighter: return .highlighter
        case .pen: return .pen
        case .pixelate: return .pixelate
        }
    }

    static func forShortcut(_ c: Character) -> Tool? {
        allCases.first { $0.shortcut == c }
    }
}

enum TextDirection: String, Codable, CaseIterable, Identifiable {
    case auto, ltr, rtl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .ltr: return "LTR"
        case .rtl: return "RTL"
        }
    }

    func isRTL(for text: String) -> Bool {
        switch self {
        case .ltr: return false
        case .rtl: return true
        case .auto: return TextDirection.detectRTL(text)
        }
    }

    /// Returns true when the first strongly-directional character is Arabic, Hebrew or another RTL script.
    static func detectRTL(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x0590...0x08FF).contains(v)      // Hebrew, Arabic, Syriac, Thaana, NKo, Arabic Extended
                || (0xFB1D...0xFDFF).contains(v)  // Hebrew & Arabic presentation forms A
                || (0xFE70...0xFEFF).contains(v)  // Arabic presentation forms B
                || (0x10800...0x10FFF).contains(v)
                || (0x1E800...0x1EFFF).contains(v) {
                return true
            }
            if scalar.properties.isAlphabetic { return false }
        }
        return false
    }
}

enum TextStyleKind: String, Codable, CaseIterable, Identifiable {
    case plain, background, outline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain: return "Plain"
        case .background: return "Bubble"
        case .outline: return "Outline"
        }
    }
}

struct FontChoice: Identifiable, Hashable {
    let name: String
    let title: String
    var id: String { name }

    static let all: [FontChoice] = [
        FontChoice(name: "", title: "System"),
        FontChoice(name: "HelveticaNeue-Bold", title: "Helvetica Neue"),
        FontChoice(name: "AvenirNext-DemiBold", title: "Avenir Next"),
        FontChoice(name: "Menlo-Bold", title: "Menlo"),
        FontChoice(name: "MarkerFelt-Wide", title: "Marker Felt"),
        FontChoice(name: "GeezaPro-Bold", title: "Geeza Pro (عربي)"),
        FontChoice(name: "KufiStandardGK", title: "Kufi (عربي)"),
        FontChoice(name: "DecoTypeNaskh", title: "Naskh (عربي)"),
        FontChoice(name: "Baghdad", title: "Baghdad (عربي)"),
    ]
}

/// Visual style of an annotation. Sizes are in points and multiplied by the image's pixel scale when drawn.
struct AnnotationStyle: Codable, Hashable {
    var color: RGBAColor = .red
    var lineWidth: CGFloat = 4
    var fontSize: CGFloat = 22
    var fontName: String = ""
    var textDirection: TextDirection = .auto
    var textStyle: TextStyleKind = .background
    var shadow: Bool = true

    func font(size: CGFloat) -> NSFont {
        if !fontName.isEmpty, let f = NSFont(name: fontName, size: size) { return f }
        return NSFont.systemFont(ofSize: size, weight: .semibold)
    }
}

/// An annotation, positioned in image pixel coordinates (top-left origin).
struct Annotation: Identifiable, Equatable {
    var id = UUID()
    var kind: AnnotationKind
    var start: CGPoint
    var end: CGPoint
    var points: [CGPoint] = []
    var style: AnnotationStyle
    var text: String = ""
    var number: Int = 0

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    mutating func offset(by d: CGPoint) {
        start.x += d.x; start.y += d.y
        end.x += d.x; end.y += d.y
        points = points.map { CGPoint(x: $0.x + d.x, y: $0.y + d.y) }
    }
}

// MARK: - Background

enum BackgroundFill: String, Codable, CaseIterable, Identifiable {
    case gradient, solid, custom, transparent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gradient: return "Gradient"
        case .solid: return "Solid"
        case .custom: return "Custom"
        case .transparent: return "None"
        }
    }
}

enum AspectRatio: String, Codable, CaseIterable, Identifiable {
    case auto, square, fourThree, threeTwo, sixteenTen, sixteenNine, nineSixteen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .square: return "1:1"
        case .fourThree: return "4:3"
        case .threeTwo: return "3:2"
        case .sixteenTen: return "16:10"
        case .sixteenNine: return "16:9"
        case .nineSixteen: return "9:16"
        }
    }

    var value: CGFloat? {
        switch self {
        case .auto: return nil
        case .square: return 1
        case .fourThree: return 4.0 / 3.0
        case .threeTwo: return 3.0 / 2.0
        case .sixteenTen: return 16.0 / 10.0
        case .sixteenNine: return 16.0 / 9.0
        case .nineSixteen: return 9.0 / 16.0
        }
    }
}

enum ContentAlignment: String, Codable, CaseIterable {
    case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight

    /// Position of the screenshot inside the free space: 0 = start, 0.5 = middle, 1 = end.
    var unit: CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .top: return CGPoint(x: 0.5, y: 0)
        case .topRight: return CGPoint(x: 1, y: 0)
        case .left: return CGPoint(x: 0, y: 0.5)
        case .center: return CGPoint(x: 0.5, y: 0.5)
        case .right: return CGPoint(x: 1, y: 0.5)
        case .bottomLeft: return CGPoint(x: 0, y: 1)
        case .bottom: return CGPoint(x: 0.5, y: 1)
        case .bottomRight: return CGPoint(x: 1, y: 1)
        }
    }
}

struct GradientPreset {
    let name: String
    let colors: [RGBAColor]
    let angle: Double

    static let all: [GradientPreset] = [
        GradientPreset(name: "Ocean", colors: [RGBAColor(hex: 0x4FACFE), RGBAColor(hex: 0x00F2FE)], angle: 135),
        GradientPreset(name: "Sunset", colors: [RGBAColor(hex: 0xFA709A), RGBAColor(hex: 0xFEE140)], angle: 135),
        GradientPreset(name: "Lavender", colors: [RGBAColor(hex: 0xA18CD1), RGBAColor(hex: 0xFBC2EB)], angle: 135),
        GradientPreset(name: "Mint", colors: [RGBAColor(hex: 0x43E97B), RGBAColor(hex: 0x38F9D7)], angle: 135),
        GradientPreset(name: "Indigo", colors: [RGBAColor(hex: 0x667EEA), RGBAColor(hex: 0x764BA2)], angle: 135),
        GradientPreset(name: "Peach", colors: [RGBAColor(hex: 0xFF9A9E), RGBAColor(hex: 0xFECFEF)], angle: 135),
        GradientPreset(name: "Night", colors: [RGBAColor(hex: 0x0F2027), RGBAColor(hex: 0x203A43), RGBAColor(hex: 0x2C5364)], angle: 135),
        GradientPreset(name: "Flame", colors: [RGBAColor(hex: 0xF12711), RGBAColor(hex: 0xF5AF19)], angle: 135),
        GradientPreset(name: "Sky", colors: [RGBAColor(hex: 0x89F7FE), RGBAColor(hex: 0x66A6FF)], angle: 135),
        GradientPreset(name: "Graphite", colors: [RGBAColor(hex: 0x434343), RGBAColor(hex: 0x000000)], angle: 135),
    ]
}

struct BackgroundSettings: Codable, Hashable {
    var enabled = false
    var fill: BackgroundFill = .gradient
    var gradientIndex = 0
    var solidColor = RGBAColor(hex: 0x1F2937)
    var customStart = RGBAColor(hex: 0x6366F1)
    var customEnd = RGBAColor(hex: 0xEC4899)
    var customAngle: Double = 135
    /// Padding, corner radius and shadow are in points.
    var padding: CGFloat = 48
    var cornerRadius: CGFloat = 12
    var shadow: CGFloat = 24
    var shadowOpacity: CGFloat = 0.45
    var aspectRatio: AspectRatio = .auto
    var alignment: ContentAlignment = .center

    var gradientColors: [RGBAColor] {
        switch fill {
        case .custom: return [customStart, customEnd]
        default:
            let index = min(max(gradientIndex, 0), GradientPreset.all.count - 1)
            return GradientPreset.all[index].colors
        }
    }

    var gradientAngle: Double {
        fill == .custom ? customAngle : GradientPreset.all[min(max(gradientIndex, 0), GradientPreset.all.count - 1)].angle
    }
}

// MARK: - Export

enum ExportFormat: String, Codable, CaseIterable, Identifiable {
    case png, jpeg, heic, tiff

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .tiff: return "tiff"
        }
    }

    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .tiff: return .tiff
        }
    }

    var supportsQuality: Bool { self == .jpeg || self == .heic }
}

enum ResizeMode: String, Codable, CaseIterable, Identifiable {
    case original, percent, width

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .percent: return "Percent"
        case .width: return "Width"
        }
    }
}

struct ExportOptions: Codable, Hashable {
    var format: ExportFormat = .png
    var quality: Double = 0.9
    var resizeMode: ResizeMode = .original
    var percent: Double = 50
    var width: Int = 1600

    /// Multiplier applied to the rendered canvas (in pixels).
    func factor(canvasWidth: CGFloat) -> CGFloat {
        switch resizeMode {
        case .original: return 1
        case .percent: return CGFloat(max(1, min(percent, 400))) / 100
        case .width: return canvasWidth > 0 ? CGFloat(max(16, width)) / canvasWidth : 1
        }
    }
}

// MARK: - Presets

struct Preset: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var background: BackgroundSettings
    var style: AnnotationStyle
    var export: ExportOptions

    static var builtIns: [Preset] {
        var ocean = BackgroundSettings()
        ocean.enabled = true
        ocean.gradientIndex = 0
        ocean.padding = 56

        var sunset = ocean
        sunset.gradientIndex = 1

        var dark = BackgroundSettings()
        dark.enabled = true
        dark.fill = .solid
        dark.solidColor = RGBAColor(hex: 0x111827)
        dark.padding = 64
        dark.shadow = 40

        var social = ocean
        social.gradientIndex = 4
        social.aspectRatio = .sixteenNine
        social.padding = 72

        return [
            Preset(name: "Plain", background: BackgroundSettings(), style: AnnotationStyle(), export: ExportOptions()),
            Preset(name: "Ocean Frame", background: ocean, style: AnnotationStyle(), export: ExportOptions()),
            Preset(name: "Sunset Frame", background: sunset, style: AnnotationStyle(color: .blue), export: ExportOptions()),
            Preset(name: "Dark Brand", background: dark, style: AnnotationStyle(color: .yellow), export: ExportOptions()),
            Preset(name: "Social 16:9", background: social, style: AnnotationStyle(), export: ExportOptions(format: .jpeg)),
        ]
    }
}

// MARK: - Document

struct CaptureResult: @unchecked Sendable {
    let image: CGImage
    /// Pixels per point (2 for Retina captures).
    let scale: CGFloat
}

struct EditorDocument {
    var image: CGImage
    var scale: CGFloat
    /// Visible part of the image, in image pixels.
    var crop: CGRect
    var annotations: [Annotation] = []
    var background = BackgroundSettings()

    init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = max(1, scale)
        self.crop = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    }

    var imageSize: CGSize { CGSize(width: image.width, height: image.height) }
    var fullRect: CGRect { CGRect(origin: .zero, size: imageSize) }
}
