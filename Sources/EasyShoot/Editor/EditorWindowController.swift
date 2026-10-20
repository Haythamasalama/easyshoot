import AppKit
import SwiftUI

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let model: EditorModel
    var onClose: ((EditorWindowController) -> Void)?

    init(result: CaptureResult) {
        model = EditorModel(result: result, preset: PresetStore.shared.defaultPreset, lastUsed: LastUsedStore.load())
        model.rememberSettings()

        // Open on the screen the pointer is on, which is where the capture just happened.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let imagePoints = CGSize(width: CGFloat(result.image.width) / result.scale,
                                 height: CGFloat(result.image.height) / result.scale)
        let size = Self.initialContentSize(imagePoints: imagePoints, visibleFrame: visible)

        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "EasyShoot"
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minimumSize
        window.tabbingMode = .disallowed
        super.init(window: window)

        window.contentView = NSHostingView(rootView: EditorView(model: model, presets: PresetStore.shared))
        window.delegate = self
        // Centre it on the screen the capture came from (center() would use the main display), never above its top.
        let frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: size))
        window.setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2,
                                      y: max(visible.minY, min(visible.midY - frame.height / 2, visible.maxY - frame.height))))
        model.window = window
    }

    static let minimumSize = CGSize(width: 860, height: 520)

    /// Big enough to show the image at 100% with the inspector and some margin, but never more
    /// than 90% of the screen and never less than the minimum window size.
    static func initialContentSize(imagePoints: CGSize, visibleFrame: CGRect) -> CGSize {
        let chrome = CGSize(width: EditorView.inspectorWidth + 120, height: 200)
        let maxSize = CGSize(width: max(minimumSize.width, visibleFrame.width * 0.9),
                             height: max(minimumSize.height, visibleFrame.height * 0.9))
        return CGSize(width: min(max(imagePoints.width + chrome.width, 900), maxSize.width),
                      height: min(max(imagePoints.height + chrome.height, 600), maxSize.height))
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
        ColorPanelBridge.shared.detach()
        AppActivation.windowClosed()
        onClose?(self)
    }

    // MARK: Menu commands (the window delegate is in the responder chain)

    @objc func saveImage(_ sender: Any?) { model.saveQuick() }
    @objc func saveImageAs(_ sender: Any?) { model.saveAs() }

    @objc func toggleInspector(_ sender: Any?) {
        let defaults = UserDefaults.standard
        defaults.set(!Self.inspectorShown, forKey: "showInspector")
    }

    private static var inspectorShown: Bool {
        UserDefaults.standard.object(forKey: "showInspector") as? Bool ?? true
    }
}

extension EditorWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleInspector(_:)) {
            menuItem.title = Self.inspectorShown ? L("Hide Inspector") : L("Show Inspector")
        }
        return true
    }
}
