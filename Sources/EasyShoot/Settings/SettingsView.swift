import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var presets: PresetStore

    var body: some View {
        TabView {
            GeneralSettings(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            PresetSettings(presets: presets)
                .tabItem { Label("Presets", systemImage: "wand.and.stars") }
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            PermissionSettings()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .padding(16)
        .frame(width: 560, height: 460)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("After capture") {
                Toggle("Show Quick Access overlay", isOn: $settings.showQuickAccess)
                Toggle("Open the editor immediately", isOn: $settings.openEditorAfterCapture)
                Toggle("Copy to clipboard", isOn: $settings.copyAfterCapture)
                Toggle("Save to folder", isOn: $settings.saveAfterCapture)
                Picker("Close Quick Access after", selection: $settings.quickAccessAutoClose) {
                    Text("Never").tag(0.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                }
            }
            Section("Capture") {
                Toggle("Play sound", isOn: $settings.playSound)
                Toggle("Include window shadow", isOn: $settings.captureWindowShadow)
            }
            Section("Save location") {
                HStack {
                    Text(settings.saveDirectory.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") { chooseFolder() }
                }
                Text("Screenshots are only stored on this Mac — EasyShoot never uploads anything.")
                    .font(.caption)
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

private struct PresetSettings: View {
    @ObservedObject var presets: PresetStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The default preset is applied to every new screenshot (background, annotation style and export format). Create presets from the editor’s Presets menu.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach($presets.presets) { $preset in
                    HStack(spacing: 10) {
                        PresetThumbnail(preset: preset)
                        TextField("Name", text: $preset.name)
                            .textFieldStyle(.plain)
                        Spacer()
                        if presets.defaultPresetID == preset.id {
                            Text("Default")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                        } else {
                            Button("Make Default") { presets.defaultPresetID = preset.id }
                        }
                        Button(role: .destructive) {
                            presets.remove(preset.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack {
                Button("No Default") { presets.defaultPresetID = nil }
                    .disabled(presets.defaultPresetID == nil)
                Spacer()
                Button("Restore Built-in Presets") { presets.restoreBuiltIns() }
            }
        }
    }
}

private struct PresetThumbnail: View {
    let preset: Preset

    var body: some View {
        let bg = preset.background
        ZStack {
            if bg.enabled {
                switch bg.fill {
                case .solid:
                    RoundedRectangle(cornerRadius: 4).fill(bg.solidColor.color)
                case .transparent:
                    RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.5))
                case .gradient, .custom:
                    GradientSwatch(colors: bg.gradientColors, angle: bg.gradientAngle)
                }
            } else {
                RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15))
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white)
                .frame(width: 22, height: 14)
                .shadow(radius: bg.enabled ? 1.5 : 0)
        }
        .frame(width: 40, height: 28)
    }
}

private struct ShortcutSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Shortcut.all, id: \.title) { shortcut in
                HStack {
                    Text(shortcut.title)
                    Spacer()
                    Text("\(Shortcut.display)\(shortcut.key)")
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15)))
                }
            }
            Divider()
            Text("Tip: during area capture press Space to switch to window capture, and Esc to cancel. In the editor, use single letters to switch tools (A arrow, T text, R rectangle, C crop…).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(8)
    }
}

private struct PermissionSettings: View {
    @State private var screen = false
    @State private var accessibility = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            row(title: "Screen Recording", detail: "Required for all screenshots.", granted: screen) {
                _ = CGRequestScreenCaptureAccess()
                Permissions.openScreenRecordingSettings()
            }
            row(title: "Accessibility", detail: "Optional — lets Scrolling Capture scroll for you (Auto-scroll).", granted: accessibility) {
                Permissions.requestAccessibility()
                Permissions.openAccessibilitySettings()
            }
            Text("After enabling Screen Recording, quit and reopen EasyShoot.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Refresh", action: refresh)
        }
        .padding(8)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        screen = Permissions.hasScreenRecording
        accessibility = Permissions.hasAccessibility
    }

    private func row(title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .font(.title2)
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Open Settings", action: action)
            }
        }
    }
}
