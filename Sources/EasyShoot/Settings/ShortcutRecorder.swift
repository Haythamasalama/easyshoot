import AppKit
import SwiftUI

/// Click, then press the new shortcut. Esc cancels, ⌫ clears.
struct ShortcutRecorder: View {
    let action: HotKeyAction
    @ObservedObject var store: ShortcutStore

    @State private var recording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        HStack(spacing: 6) {
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Button(action: toggle) {
                Text(label)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(recording ? Brand.signal : (store.combo(for: action) == nil ? .secondary : .primary))
                    .frame(minWidth: 96)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(recording ? Brand.signal.opacity(0.12) : Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(recording ? Brand.signal : Color.primary.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(L("Click and press a new shortcut. Esc cancels, Delete clears."))

            if store.combo(for: action) != nil && !recording {
                Button {
                    store.set(nil, for: action)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(L("Clear shortcut"))
                .accessibilityLabel(L("Clear shortcut"))
            }
        }
        .animation(.easeOut(duration: 0.15), value: hint)
        .onDisappear(perform: stop)
        // Another recorder started, or the Settings window closed (which may not send onDisappear).
        .onChange(of: store.recordingAction) { _, active in
            if recording, active != action { stop() }
        }
        .onChange(of: store.isRecording) { _, isRecording in
            if recording, !isRecording { stop() }
        }
    }

    private var label: String {
        if recording { return L("Type shortcut…") }
        return store.combo(for: action)?.displayString ?? L("Record Shortcut")
    }

    private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        recording = true
        hint = nil
        store.recordingAction = action
        store.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        // Leave the store alone if another recorder has already taken over.
        if store.recordingAction == action || store.recordingAction == nil {
            store.recordingAction = nil
            store.isRecording = false
        }
    }

    private func handle(_ event: NSEvent) {
        let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        if plain && event.keyCode == 53 { // Esc
            stop()
            return
        }
        if plain && (event.keyCode == 51 || event.keyCode == 117) { // Delete
            store.set(nil, for: action)
            stop()
            return
        }
        guard let combo = KeyCombo(event: event) else {
            hint = L("Use ⌘ or ⌃ with a key")
            NSSound.beep()
            return
        }
        if let other = store.conflictingAction(for: combo, excluding: action) {
            hint = L("Moved from “%@”", other.title)
        } else {
            hint = nil
        }
        store.set(combo, for: action)
        stop()
    }
}
