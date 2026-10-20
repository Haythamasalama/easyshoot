import AppKit
import Carbon.HIToolbox

/// A key plus modifiers, stored with Carbon modifier flags so it can be registered as a global hotkey.
struct KeyCombo: Codable, Hashable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    /// Printable key name, e.g. "4", "S", "F5", "Space".
    var key: String

    var displayString: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + key
    }

    var eventModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    /// Key equivalent for NSMenuItem (single characters only).
    var menuKeyEquivalent: String { key.count == 1 ? key.lowercased() : "" }

    static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
    ]

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    static func isFunctionKey(_ keyCode: UInt16) -> Bool { functionKeys[Int(keyCode)] != nil }

    /// Builds a combo from a key press, or nil if it isn't usable as a global shortcut.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = Int(event.keyCode)
        let name: String
        if let f = Self.functionKeys[code] {
            name = f
        } else if let n = Self.namedKeys[code] {
            name = n
        } else if let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty,
                  chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
            name = chars
        } else {
            return nil
        }
        // Plain letters would break typing everywhere: require ⌘, ⌥ or ⌃ unless it's a function key.
        let hasStrongModifier = !flags.intersection([.command, .option, .control]).isEmpty
        guard hasStrongModifier || Self.functionKeys[code] != nil else { return nil }
        self.init(keyCode: UInt32(code), carbonModifiers: Self.carbonFlags(from: flags), key: name)
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.key = key
    }
}

enum HotKeyAction: String, CaseIterable, Codable, Identifiable {
    case captureArea, captureWindow, captureFullscreen, scrollingCapture, annotateClipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captureArea: return L("Capture Area")
        case .captureWindow: return L("Capture Window")
        case .captureFullscreen: return L("Capture Fullscreen")
        case .scrollingCapture: return L("Scrolling Capture")
        case .annotateClipboard: return L("Annotate Clipboard Image")
        }
    }

    var symbol: String {
        switch self {
        case .captureArea: return "rectangle.dashed"
        case .captureWindow: return "macwindow"
        case .captureFullscreen: return "display"
        case .scrollingCapture: return "arrow.up.and.down.text.horizontal"
        case .annotateClipboard: return "doc.on.clipboard"
        }
    }

    /// ⌥⇧⌘ + number, so the defaults never clash with macOS's own ⇧⌘3/4/5.
    var defaultCombo: KeyCombo {
        let mods = UInt32(cmdKey | shiftKey | optionKey)
        switch self {
        case .captureArea: return KeyCombo(keyCode: UInt32(kVK_ANSI_4), carbonModifiers: mods, key: "4")
        case .captureWindow: return KeyCombo(keyCode: UInt32(kVK_ANSI_5), carbonModifiers: mods, key: "5")
        case .captureFullscreen: return KeyCombo(keyCode: UInt32(kVK_ANSI_3), carbonModifiers: mods, key: "3")
        case .scrollingCapture: return KeyCombo(keyCode: UInt32(kVK_ANSI_6), carbonModifiers: mods, key: "6")
        case .annotateClipboard: return KeyCombo(keyCode: UInt32(kVK_ANSI_7), carbonModifiers: mods, key: "7")
        }
    }
}

/// User-editable global shortcuts. Changes re-register the hotkeys immediately.
@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    @Published private(set) var combos: [HotKeyAction: KeyCombo]
    /// Set while a recorder is listening, so pressing an existing shortcut doesn't trigger a capture.
    @Published var isRecording = false { didSet { onChange?() } }

    var onChange: (() -> Void)?

    private static let key = "customShortcuts.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode([String: KeyCombo?].self, from: data) {
            var result: [HotKeyAction: KeyCombo] = [:]
            for action in HotKeyAction.allCases {
                if let entry = stored[action.rawValue] {
                    if let combo = entry { result[action] = combo } // nil = user cleared it
                } else {
                    result[action] = action.defaultCombo
                }
            }
            combos = result
        } else {
            combos = Dictionary(uniqueKeysWithValues: HotKeyAction.allCases.map { ($0, $0.defaultCombo) })
        }
    }

    func combo(for action: HotKeyAction) -> KeyCombo? { combos[action] }

    /// Assigns a shortcut; if another action used the same keys, that one is cleared.
    func set(_ combo: KeyCombo?, for action: HotKeyAction) {
        if let combo {
            for (other, existing) in combos where other != action && existing == combo {
                combos[other] = nil
            }
        }
        combos[action] = combo
        save()
    }

    func conflictingAction(for combo: KeyCombo, excluding action: HotKeyAction) -> HotKeyAction? {
        combos.first { $0.key != action && $0.value == combo }?.key
    }

    func resetAll() {
        combos = Dictionary(uniqueKeysWithValues: HotKeyAction.allCases.map { ($0, $0.defaultCombo) })
        save()
    }

    private func save() {
        var stored: [String: KeyCombo?] = [:]
        for action in HotKeyAction.allCases { stored[action.rawValue] = combos[action] }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        onChange?()
    }
}
