import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private let coordinator = CaptureCoordinator.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        setupStatusItem()
        registerHotKeys()
        if !Permissions.hasScreenRecording {
            _ = CGRequestScreenCaptureAccess()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregisterAll()
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "EasyShoot")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        addItem(to: menu, Shortcut.captureArea, #selector(captureArea(_:)))
        addItem(to: menu, Shortcut.captureWindow, #selector(captureWindow(_:)))
        addItem(to: menu, Shortcut.captureFullscreen, #selector(captureFullscreen(_:)))
        addItem(to: menu, Shortcut.scrollingCapture, #selector(scrollingCapture(_:)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Open Image…", #selector(openImage(_:))))
        addItem(to: menu, Shortcut.openLast, #selector(annotateClipboard(_:)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", #selector(openSettings(_:)), key: ","))
        menu.addItem(makeItem("Quit EasyShoot", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
        item.menu = menu
        statusItem = item
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    private func addItem(to menu: NSMenu, _ shortcut: Shortcut, _ action: Selector) {
        let item = makeItem(shortcut.title, action, key: shortcut.key)
        item.keyEquivalentModifierMask = [.command, .shift, .option]
        menu.addItem(item)
    }

    private func registerHotKeys() {
        let hotKeys = HotKeyManager.shared
        let mods = Shortcut.modifiers
        hotKeys.register(keyCode: Shortcut.captureArea.keyCode, modifiers: mods) { [weak self] in self?.coordinator.capture(.area) }
        hotKeys.register(keyCode: Shortcut.captureWindow.keyCode, modifiers: mods) { [weak self] in self?.coordinator.capture(.window) }
        hotKeys.register(keyCode: Shortcut.captureFullscreen.keyCode, modifiers: mods) { [weak self] in self?.coordinator.capture(.fullscreen) }
        hotKeys.register(keyCode: Shortcut.scrollingCapture.keyCode, modifiers: mods) { [weak self] in self?.coordinator.startScrollingCapture() }
        hotKeys.register(keyCode: Shortcut.openLast.keyCode, modifiers: mods) { [weak self] in self?.coordinator.annotateClipboard() }
    }

    // MARK: Actions

    @objc func captureArea(_ sender: Any?) { coordinator.capture(.area) }
    @objc func captureWindow(_ sender: Any?) { coordinator.capture(.window) }
    @objc func captureFullscreen(_ sender: Any?) { coordinator.capture(.fullscreen) }
    @objc func scrollingCapture(_ sender: Any?) { coordinator.startScrollingCapture() }
    @objc func openImage(_ sender: Any?) { coordinator.openImageFile() }
    @objc func annotateClipboard(_ sender: Any?) { coordinator.annotateClipboard() }

    @objc func openSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 460),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "EasyShoot Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: .shared, presets: .shared))
            window.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { AppActivation.windowClosed() }
            }
            settingsWindow = window
        }
        if settingsWindow?.isVisible == false { AppActivation.windowOpened() }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
