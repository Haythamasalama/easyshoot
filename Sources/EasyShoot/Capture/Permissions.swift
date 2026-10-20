import AppKit
import ApplicationServices

@MainActor
enum Permissions {
    static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Returns true if screen capture is allowed; otherwise asks for it and explains how to enable it.
    static func ensureScreenRecording() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        if CGRequestScreenCaptureAccess() { return true }
        let alert = NSAlert()
        alert.messageText = L("Allow Screen Recording")
        alert.informativeText = L("EasyShoot needs Screen Recording permission to take screenshots.\n\nOpen System Settings → Privacy & Security → Screen & System Audio Recording, enable EasyShoot, then quit and reopen EasyShoot.")
        alert.addButton(withTitle: L("Open System Settings"))
        alert.addButton(withTitle: L("Cancel"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { openScreenRecordingSettings() }
        return false
    }

    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
