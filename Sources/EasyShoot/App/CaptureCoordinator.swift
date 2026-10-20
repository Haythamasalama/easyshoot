import AppKit
import UniformTypeIdentifiers

/// Runs captures and decides what happens afterwards (Quick Access, copy, save, editor).
@MainActor
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    private var editors: [EditorWindowController] = []
    private var scrolling: ScrollingCaptureController?
    private var regionSelector: RegionSelector?
    private var isCapturing = false

    /// True while a screenshot is being taken in any way, so nothing else (like an update offer) pops up.
    var isBusy: Bool { isCapturing || scrolling != nil || regionSelector != nil }

    func capture(_ mode: CaptureMode) {
        guard !isBusy, Permissions.ensureScreenRecording() else { return }
        isCapturing = true
        QuickAccessManager.shared.setHidden(true)
        let settings = AppSettings.shared
        Task {
            let result = await ScreenshotService.capture(mode, sound: settings.playSound, windowShadow: settings.captureWindowShadow)
            QuickAccessManager.shared.setHidden(false)
            isCapturing = false
            if let result { handle(result) }
        }
    }

    func startScrollingCapture() {
        guard !isBusy, Permissions.ensureScreenRecording() else { return }
        QuickAccessManager.shared.setHidden(true)
        let selector = RegionSelector()
        regionSelector = selector
        selector.begin(message: L("Drag over the area you want to scroll · Esc to cancel")) { [weak self] rect, screen in
            guard let self else { return }
            self.regionSelector = nil
            guard let rect, let screen else {
                QuickAccessManager.shared.setHidden(false)
                return
            }
            let controller = ScrollingCaptureController(rect: rect, screen: screen)
            controller.onFinish = { [weak self] image, scale in
                guard let self else { return }
                self.scrolling = nil
                QuickAccessManager.shared.setHidden(false)
                if let image {
                    if AppSettings.shared.playSound { NSSound(named: "Glass")?.play() }
                    self.handle(CaptureResult(image: image, scale: scale))
                }
            }
            self.scrolling = controller
            controller.start()
        }
    }

    func handle(_ result: CaptureResult) {
        let settings = AppSettings.shared
        if settings.copyAfterCapture || settings.saveAfterCapture,
           let rendered = ExportService.renderWithDefaults(result) {
            if settings.copyAfterCapture {
                ExportService.copyToPasteboard(rendered.image, dpiScale: rendered.dpiScale)
            }
            if settings.saveAfterCapture {
                do {
                    _ = try ExportService.save(rendered.image, options: rendered.options, dpiScale: rendered.dpiScale,
                                               to: ExportService.defaultSaveURL(for: rendered.options.format))
                } catch {
                    // For example the save folder is on a drive that's no longer connected: say so, never lose it silently.
                    NSApp.activate()
                    NSAlert(error: error).runModal()
                }
            }
        }
        if settings.openEditorAfterCapture {
            openEditor(result)
        } else if settings.showQuickAccess {
            QuickAccessManager.shared.show(result)
        }
    }

    func openEditor(_ result: CaptureResult) {
        let controller = EditorWindowController(result: result)
        controller.onClose = { [weak self] closed in
            self?.editors.removeAll { $0 === closed }
        }
        editors.append(controller)
        controller.show()
    }

    func openImageFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let result = ScreenshotService.loadImage(url: url) { openEditor(result) }
        }
    }

    func annotateClipboard() {
        if let result = ScreenshotService.imageFromPasteboard() {
            openEditor(result)
        } else {
            NSSound.beep()
        }
    }
}
