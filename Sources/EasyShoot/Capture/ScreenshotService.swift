import AppKit
import ImageIO

enum CaptureMode {
    case area, window, fullscreen
}

/// Uses macOS's built-in `screencapture` tool for the interactive selection UI
/// (area with crosshair, Space to toggle window mode, Esc to cancel).
@MainActor
enum ScreenshotService {
    static func capture(_ mode: CaptureMode, sound: Bool, windowShadow: Bool) async -> CaptureResult? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("easyshoot-\(UUID().uuidString)")
            .appendingPathExtension("png")

        var args = ["-t", "png"]
        switch mode {
        case .area: args.append("-i")
        case .window: args += ["-i", "-w"]
        case .fullscreen: args += ["-D", String(displayNumberUnderPointer())]
        }
        if !sound { args.append("-x") }
        if mode == .window && !windowShadow { args.append("-o") }
        args.append(url.path)

        let succeeded: Bool = await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = args
            process.terminationHandler = { _ in
                _ = process // keep the process alive until it exits
                continuation.resume(returning: true)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
        defer { try? FileManager.default.removeItem(at: url) }
        guard succeeded, let data = try? Data(contentsOf: url) else { return nil } // no file = user cancelled
        return loadImage(data: data)
    }

    /// screencapture numbers displays from 1 in the system's active-display order (1 is the main display).
    /// Capture Fullscreen takes the display the pointer is on, like the other capture modes.
    private static func displayNumberUnderPointer() -> Int {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
              let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        else { return 1 }
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return 1 }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return 1 }
        return (ids.firstIndex(of: id) ?? 0) + 1
    }

    /// Loads image data and works out its pixel scale from the DPI metadata (144 dpi = Retina @2x).
    /// Print-resolution files (300 dpi scans) are capped at @3x so they don't open tiny with huge strokes.
    static func loadImage(data: Data) -> CaptureResult? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        var scale = NSScreen.main?.backingScaleFactor ?? 2
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let dpi = (props[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue, dpi > 0, dpi.isFinite {
            scale = min(3, max(1, CGFloat((dpi / 72).rounded())))
        }
        return CaptureResult(image: image, scale: scale)
    }

    static func loadImage(url: URL) -> CaptureResult? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return loadImage(data: data)
    }

    static func imageFromPasteboard() -> CaptureResult? {
        let pasteboard = NSPasteboard.general
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), let result = loadImage(data: data) { return result }
        }
        if let image = NSImage(pasteboard: pasteboard),
           let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let scale = image.size.width > 0 ? min(3, max(1, (CGFloat(cg.width) / image.size.width).rounded())) : 1
            return CaptureResult(image: cg, scale: scale)
        }
        return nil
    }
}
