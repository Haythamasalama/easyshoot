import AppKit
import SwiftUI

/// First-run window: explains that EasyShoot lives in the menu bar, gets Screen Recording
/// permission sorted, and lists the shortcuts. Also shown when the app is opened again from Finder.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindowController()

    private static let seenKey = "hasSeenWelcome"
    private static let showAtLaunchKey = "showWelcomeAtLaunch"
    private var window: NSWindow?

    var shouldShowAtLaunch: Bool {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.seenKey) { return true }
        if !Permissions.hasScreenRecording { return true }
        return defaults.object(forKey: Self.showAtLaunchKey) as? Bool ?? false
    }

    func show() {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        if window == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 640),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: WelcomeView(close: { [weak self] in self?.close() }))
            window.center()
            self.window = window
            AppActivation.windowOpened()
        } else if window?.isVisible == false {
            AppActivation.windowOpened()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        AppActivation.windowClosed()
    }

    static func setShowAtLaunch(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: showAtLaunchKey)
    }

    static var showAtLaunchPreference: Bool {
        UserDefaults.standard.object(forKey: showAtLaunchKey) as? Bool ?? false
    }

    /// macOS only applies a new Screen Recording permission after the app restarts.
    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}

struct WelcomeView: View {
    let close: () -> Void

    @State private var hasScreenRecording = true
    @State private var requestedPermission = false
    @State private var showAtLaunch = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                Text("Welcome to EasyShoot")
                    .font(.system(size: 26, weight: .bold))
                Text("\(Brand.tagline)  ·  \(Brand.taglineArabic)")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 36)
            .padding(.bottom, 24)

            VStack(spacing: 12) {
                card {
                    HStack(alignment: .top, spacing: 14) {
                        Image(nsImage: Brand.menuBarImage(size: 22))
                            .renderingMode(.template)
                            .foregroundStyle(Brand.signal)
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Brand.signal.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("EasyShoot lives in your menu bar").font(.headline)
                            Text("There’s no main window. Look for this icon at the top-right of your screen. On a MacBook with a notch it can be hidden, so the keyboard shortcuts below always work.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                card { permissionRow }

                card {
                    VStack(spacing: 8) {
                        shortcutRow("Capture Area", "4")
                        shortcutRow("Capture Window", "5")
                        shortcutRow("Capture Fullscreen", "3")
                        shortcutRow("Scrolling Capture", "6")
                    }
                }
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 16)

            HStack {
                Toggle("Show at launch", isOn: $showAtLaunch)
                    .toggleStyle(.checkbox)
                    .onChange(of: showAtLaunch) { _, value in WelcomeWindowController.setShowAtLaunch(value) }
                Spacer()
                Button("Done", action: close)
                    .keyboardShortcut(.cancelAction)
                Button {
                    close()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        CaptureCoordinator.shared.capture(.area)
                    }
                } label: {
                    Label("Take a Screenshot", systemImage: "camera.viewfinder")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasScreenRecording)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 520, height: 640)
        .tint(Brand.signal)
        .onReceive(timer) { _ in hasScreenRecording = Permissions.hasScreenRecording }
        .onAppear {
            hasScreenRecording = Permissions.hasScreenRecording
            showAtLaunch = WelcomeWindowController.showAtLaunchPreference
        }
    }

    @ViewBuilder
    private var permissionRow: some View {
        HStack(spacing: 14) {
            Image(systemName: hasScreenRecording ? "checkmark.circle.fill" : "lock.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(hasScreenRecording ? Color.green : Brand.signal)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text("Screen Recording permission").font(.headline)
                Text(hasScreenRecording
                     ? "All set: you can take screenshots."
                     : requestedPermission
                        ? "Turn on EasyShoot in the list, then press Restart."
                        : "Required to take screenshots. Nothing ever leaves your Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !hasScreenRecording {
                if requestedPermission {
                    Button("Restart") { WelcomeWindowController.relaunch() }
                } else {
                    Button("Allow…") {
                        _ = CGRequestScreenCaptureAccess()
                        Permissions.openScreenRecordingSettings()
                        requestedPermission = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func shortcutRow(_ title: String, _ key: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(Shortcut.display)\(key)")
                .font(.system(.body, design: .rounded).weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.045)))
    }
}
