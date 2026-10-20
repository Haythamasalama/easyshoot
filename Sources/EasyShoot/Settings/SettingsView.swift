import AppKit
import SwiftUI

/// System Settings–style window: sidebar on the left, grouped form on the right.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var presets: PresetStore
    @ObservedObject var shortcuts: ShortcutStore
    @State private var page: Page? = .general

    enum Page: String, CaseIterable, Identifiable {
        case general, shortcuts, presets, language, permissions, about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return L("General")
            case .shortcuts: return L("Shortcuts")
            case .presets: return L("Presets")
            case .language: return L("Language")
            case .permissions: return L("Permissions")
            case .about: return L("About")
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape.fill"
            case .shortcuts: return "command"
            case .presets: return "wand.and.stars"
            case .language: return "globe"
            case .permissions: return "lock.shield.fill"
            case .about: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .general: return .gray
            case .shortcuts: return Brand.signal
            case .presets: return .purple
            case .language: return .blue
            case .permissions: return .green
            case .about: return Brand.graphiteLight
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { page in
                Label {
                    Text(page.title)
                } icon: {
                    IconTile(symbol: page.symbol, color: page.color)
                }
                .tag(page)
                .padding(.vertical, 2)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            Group {
                switch page ?? .general {
                case .general: GeneralSettings(settings: settings)
                case .shortcuts: ShortcutSettings(store: shortcuts)
                case .presets: PresetSettings(presets: presets)
                case .language: LanguageSettings()
                case .permissions: PermissionSettings()
                case .about: AboutSettings()
                }
            }
            .navigationTitle((page ?? .general).title)
        }
        .frame(minWidth: 720, minHeight: 500)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section(L("After capture")) {
                Toggle(L("Show Quick Access overlay"), isOn: $settings.showQuickAccess)
                Toggle(L("Open the editor immediately"), isOn: $settings.openEditorAfterCapture)
                Toggle(L("Copy to clipboard"), isOn: $settings.copyAfterCapture)
                Toggle(L("Save to folder"), isOn: $settings.saveAfterCapture)
                Picker(L("Close Quick Access after"), selection: $settings.quickAccessAutoClose) {
                    Text(L("Never")).tag(0.0)
                    Text(L("5 seconds")).tag(5.0)
                    Text(L("10 seconds")).tag(10.0)
                    Text(L("30 seconds")).tag(30.0)
                }
            }
            Section(L("Capture")) {
                Toggle(L("Play sound"), isOn: $settings.playSound)
                Toggle(L("Include window shadow"), isOn: $settings.captureWindowShadow)
            }
            Section {
                LabeledContent(L("Save location")) {
                    HStack {
                        Text(settings.saveDirectory.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button(L("Choose…"), action: chooseFolder)
                    }
                }
            } footer: {
                Text(L("Screenshots are only stored on this Mac. EasyShoot never uploads anything."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectoryPath = url.path
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutSettings: View {
    @ObservedObject var store: ShortcutStore

    var body: some View {
        Form {
            Section {
                ForEach(HotKeyAction.allCases) { action in
                    LabeledContent {
                        ShortcutRecorder(action: action, store: store)
                    } label: {
                        Label {
                            Text(action.title)
                        } icon: {
                            Image(systemName: action.symbol).foregroundStyle(Brand.signal)
                        }
                    }
                }
            } header: {
                Text(L("Global shortcuts"))
            } footer: {
                Text(L("Click a shortcut and press new keys. Use ⌘, ⌥ or ⌃ with a key, or a function key on its own. Tip: you can take over ⇧⌘4 after turning it off in System Settings → Keyboard → Keyboard Shortcuts → Screenshots."))
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Spacer()
                    Button(L("Restore Defaults")) { store.resetAll() }
                }
            }

            Section(L("Editor")) {
                LabeledContent(L("Tools"), value: "V · C · A · L · R · F · O · T · N · H · P · B")
                LabeledContent(L("Text size"), value: "⌘+  ⌘−")
                LabeledContent(L("Undo / Redo"), value: "⌘Z  ⇧⌘Z")
                LabeledContent(L("Copy / Save"), value: "⇧⌘C  ⌘S")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Presets

private struct PresetSettings: View {
    @ObservedObject var presets: PresetStore

    var body: some View {
        Form {
            Section {
                ForEach($presets.presets) { $preset in
                    HStack(spacing: 12) {
                        PresetThumbnail(preset: preset)
                        TextField(L("Name"), text: $preset.name)
                            .textFieldStyle(.plain)
                        Spacer()
                        if presets.defaultPresetID == preset.id {
                            Text(L("Default"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Brand.signal)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Brand.signal.opacity(0.14)))
                        } else {
                            Button(L("Make Default")) { presets.defaultPresetID = preset.id }
                                .buttonStyle(.borderless)
                        }
                        Button(role: .destructive) {
                            presets.remove(preset.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text(L("Presets"))
            } footer: {
                Text(L("The default preset is applied to every new screenshot: background, annotation style and export format. Without a default, each screenshot starts with your last settings. Create presets from the editor’s Presets menu."))
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button(L("No Default")) { presets.defaultPresetID = nil }
                        .disabled(presets.defaultPresetID == nil)
                    Spacer()
                    Button(L("Restore Built-in Presets")) { presets.restoreBuiltIns() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct PresetThumbnail: View {
    let preset: Preset

    var body: some View {
        let bg = preset.background
        ZStack {
            if bg.enabled {
                switch bg.fill {
                case .solid:
                    RoundedRectangle(cornerRadius: 5).fill(bg.solidColor.color)
                case .transparent:
                    RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.5))
                case .gradient, .custom:
                    GradientSwatch(colors: bg.gradientColors, angle: bg.gradientAngle)
                }
            } else {
                RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15))
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white)
                .frame(width: 24, height: 15)
                .shadow(radius: bg.enabled ? 1.5 : 0)
        }
        .frame(width: 44, height: 30)
    }
}

// MARK: - Language

private struct LanguageSettings: View {
    @State private var selection = AppLanguage.current
    @State private var changed = false

    var body: some View {
        Form {
            Section {
                Picker(L("App language"), selection: $selection) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .onChange(of: selection) { _, value in
                    value.apply()
                    changed = true
                }
            } header: {
                Text(L("App language"))
            } footer: {
                Text(L("Arabic switches the whole interface to right-to-left."))
                    .foregroundStyle(.secondary)
            }
            if changed {
                Section {
                    HStack {
                        Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(Brand.signal)
                        Text(L("Restart EasyShoot to use the new language."))
                        Spacer()
                        Button(L("Restart Now")) { WelcomeWindowController.relaunch() }
                            .primaryButtonStyle()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Permissions

private struct PermissionSettings: View {
    @State private var screen = false
    @State private var accessibility = false

    var body: some View {
        Form {
            Section {
                row(title: L("Screen Recording"), detail: L("Required for all screenshots."), granted: screen) {
                    _ = CGRequestScreenCaptureAccess()
                    Permissions.openScreenRecordingSettings()
                }
                row(title: L("Accessibility"), detail: L("Optional. Lets Scrolling Capture scroll for you (Auto-scroll)."), granted: accessibility) {
                    Permissions.requestAccessibility()
                    Permissions.openAccessibilitySettings()
                }
            } footer: {
                Text(L("After enabling Screen Recording, quit and reopen EasyShoot."))
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button(L("Refresh"), action: refresh)
                    Spacer()
                    Button(L("Restart EasyShoot")) { WelcomeWindowController.relaunch() }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        screen = Permissions.hasScreenRecording
        accessibility = Permissions.hasAccessibility
    }

    private func row(title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : Brand.signal)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Text(L("Allowed")).foregroundStyle(.secondary)
            } else {
                Button(L("Open Settings"), action: action)
            }
        }
    }
}

// MARK: - About

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            HStack(spacing: 0) {
                Text("Easy").foregroundStyle(.primary)
                Text("Shoot").foregroundStyle(Brand.signal)
            }
            .font(.system(size: 30, weight: .heavy))
            Text(L("Version %@", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"))
                .foregroundStyle(.secondary)
            Text(L("Capture. Mark up. Share."))
                .font(.title3)
            Text(L("Screenshots stay on your Mac: no account, no cloud, no tracking."))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
