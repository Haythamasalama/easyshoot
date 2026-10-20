import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private let coordinator = CaptureCoordinator.shared
    private let shortcuts = ShortcutStore.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        FontLibrary.shared.registerDownloadedFonts()
        setupStatusItem()
        shortcuts.onChange = { [weak self] in self?.registerHotKeys() }
        registerHotKeys()
        if WelcomeWindowController.shared.shouldShowAtLaunch {
            WelcomeWindowController.shared.show()
        }
    }

    /// Opening the app again from Finder or Launchpad shows the welcome window, so it never looks like nothing happened.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WelcomeWindowController.shared.show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregisterAll()
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Brand.menuBarImage()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuildMenu(menu)
    }

    /// Rebuilt each time it opens, so titles and shortcuts are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(actionItem(.captureArea, symbol: "rectangle.dashed"))
        menu.addItem(actionItem(.captureWindow, symbol: "macwindow"))
        menu.addItem(actionItem(.captureFullscreen, symbol: "display"))
        menu.addItem(actionItem(.scrollingCapture, symbol: "arrow.up.and.down.text.horizontal"))
        menu.addItem(.separator())
        menu.addItem(makeItem(L("Open Image…"), #selector(openImage(_:)), symbol: "photo.on.rectangle"))
        menu.addItem(actionItem(.annotateClipboard, symbol: "doc.on.clipboard"))
        menu.addItem(.separator())
        menu.addItem(makeItem(L("Welcome & Permissions…"), #selector(showWelcome(_:)), symbol: "hand.wave"))
        menu.addItem(makeItem(L("Settings…"), #selector(openSettings(_:)), key: ",", symbol: "gearshape"))
        menu.addItem(.separator())
        menu.addItem(makeItem(L("Quit EasyShoot"), #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    private func actionItem(_ action: HotKeyAction, symbol: String) -> NSMenuItem {
        let item = makeItem(action.title, #selector(performAction(_:)), symbol: symbol)
        item.representedObject = action.rawValue
        if let combo = shortcuts.combo(for: action), !combo.menuKeyEquivalent.isEmpty {
            item.keyEquivalent = combo.menuKeyEquivalent
            item.keyEquivalentModifierMask = combo.eventModifiers
        }
        return item
    }

    // MARK: Hotkeys

    private func registerHotKeys() {
        let hotKeys = HotKeyManager.shared
        hotKeys.unregisterAll()
        guard !shortcuts.isRecording else { return }
        for action in HotKeyAction.allCases {
            guard let combo = shortcuts.combo(for: action) else { continue }
            hotKeys.register(keyCode: Int(combo.keyCode), modifiers: Int(combo.carbonModifiers)) { [weak self] in
                self?.perform(action)
            }
        }
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .captureArea: coordinator.capture(.area)
        case .captureWindow: coordinator.capture(.window)
        case .captureFullscreen: coordinator.capture(.fullscreen)
        case .scrollingCapture: coordinator.startScrollingCapture()
        case .annotateClipboard: coordinator.annotateClipboard()
        }
    }

    // MARK: Actions

    @objc func performAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = HotKeyAction(rawValue: raw) else { return }
        perform(action)
    }

    @objc func openImage(_ sender: Any?) { coordinator.openImageFile() }
    @objc func annotateClipboard(_ sender: Any?) { coordinator.annotateClipboard() }
    @objc func showWelcome(_ sender: Any?) { WelcomeWindowController.shared.show() }

    @objc func openSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 540),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = L("Settings")
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: .shared, presets: .shared, shortcuts: .shared)
                .tint(Brand.signal))
            window.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated {
                    ShortcutStore.shared.isRecording = false
                    AppActivation.windowClosed()
                }
            }
            settingsWindow = window
        }
        if settingsWindow?.isVisible == false { AppActivation.windowOpened() }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
