import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ExportError: LocalizedError {
    case encodingFailed

    var errorDescription: String? { "The image could not be encoded." }
}

/// Encoding, clipboard and file output. Everything stays local — no cloud.
@MainActor
enum ExportService {
    static func encode(_ image: CGImage, options: ExportOptions, dpiScale: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, options.format.utType.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: 72 * dpiScale,
            kCGImagePropertyDPIHeight: 72 * dpiScale,
        ]
        if options.format.supportsQuality {
            props[kCGImageDestinationLossyCompressionQuality] = options.quality
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    static func copyToPasteboard(_ image: CGImage, dpiScale: CGFloat) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if let png = encode(image, options: ExportOptions(format: .png), dpiScale: dpiScale) {
            item.setData(png, forType: .png)
        }
        let size = CGSize(width: CGFloat(image.width) / dpiScale, height: CGFloat(image.height) / dpiScale)
        if let tiff = NSImage(cgImage: image, size: size).tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        pasteboard.writeObjects([item])
    }

    static func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "EasyShoot \(formatter.string(from: Date()))"
    }

    static func defaultSaveURL(for format: ExportFormat) -> URL {
        let directory = AppSettings.shared.saveDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = defaultFileName()
        var url = directory.appendingPathComponent(base).appendingPathExtension(format.fileExtension)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base) (\(n))").appendingPathExtension(format.fileExtension)
            n += 1
        }
        return url
    }

    @discardableResult
    static func save(_ image: CGImage, options: ExportOptions, dpiScale: CGFloat, to url: URL) throws -> URL {
        guard let data = encode(image, options: options, dpiScale: dpiScale) else { throw ExportError.encodingFailed }
        try data.write(to: url, options: .atomic)
        return url
    }

    static func writeTemporary(_ image: CGImage, options: ExportOptions, dpiScale: CGFloat) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EasyShootDrag", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(defaultFileName()).appendingPathExtension(options.format.fileExtension)
        return try save(image, options: options, dpiScale: dpiScale, to: url)
    }

    static func saveWithPanel(_ image: CGImage, options: ExportOptions, dpiScale: CGFloat, window: NSWindow?,
                              completion: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [options.format.utType]
        panel.nameFieldStringValue = defaultFileName() + "." + options.format.fileExtension
        panel.directoryURL = AppSettings.shared.saveDirectory
        panel.canCreateDirectories = true
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { completion(nil); return }
            do {
                completion(try save(image, options: options, dpiScale: dpiScale, to: url))
            } catch {
                NSAlert(error: error).runModal()
                completion(nil)
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    /// Renders a fresh capture using the default preset (used by Quick Access and auto copy/save).
    static func renderWithDefaults(_ result: CaptureResult) -> (image: CGImage, options: ExportOptions, dpiScale: CGFloat)? {
        var doc = EditorDocument(image: result.image, scale: result.scale)
        let preset = PresetStore.shared.defaultPreset
        if let preset { doc.background = preset.background }
        let options = preset?.export ?? ExportOptions()
        let layout = Renderer.layout(for: doc)
        let factor = Renderer.safeFactor(options.factor(canvasWidth: layout.canvasSize.width), canvas: layout.canvasSize)
        if !doc.background.enabled && factor == 1 && options.format != .jpeg {
            return (result.image, options, result.scale)
        }
        guard let image = Renderer.renderImage(doc, factor: factor, pixelated: nil, opaque: options.format == .jpeg) else { return nil }
        return (image, options, result.scale * factor)
    }
}
