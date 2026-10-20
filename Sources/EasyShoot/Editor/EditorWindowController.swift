import AppKit
import SwiftUI

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let model: EditorModel
    var onClose: ((EditorWindowController) -> Void)?

    init(result: CaptureResult) {
        model = EditorModel(result: result, preset: PresetStore.shared.defaultPreset, lastUsed: LastUsedStore.load())
        model.rememberSettings()

        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let imagePoints = CGSize(width: CGFloat(result.image.width) / result.scale,
                                 height: CGFloat(result.image.height) / result.scale)
        let width = min(max(imagePoints.width + 280 + 120, 900), visible.width * 0.9)
        let height = min(max(imagePoints.height + 200, 600), visible.height * 0.9)

        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "EasyShoot"
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 860, height: 520)
        window.tabbingMode = .disallowed
        super.init(window: window)

        window.contentView = NSHostingView(rootView: EditorView(model: model, presets: PresetStore.shared))
        window.delegate = self
        window.center()
        model.window = window
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show() {
        AppActivation.windowOpened()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        model.commitPendingEdits = nil
        AppActivation.windowClosed()
        onClose?(self)
    }
}
