import Foundation

/// Localized string from Localizable.strings (the English text is the key).
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Localized format string, e.g. `L("Saved %@", name)`.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments: args)
}

/// In-app language override. Changing it takes effect after a restart (standard macOS behavior).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, ar, fr, es, de

    var id: String { rawValue }

    /// Shown in its own language so people can always find theirs.
    var nativeName: String {
        switch self {
        case .system: return L("System Default")
        case .en: return "English"
        case .ar: return "العربية"
        case .fr: return "Français"
        case .es: return "Español"
        case .de: return "Deutsch"
        }
    }

    static var current: AppLanguage {
        guard let override = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
              UserDefaults.standard.object(forKey: overrideKey) != nil,
              let first = override.first,
              let language = AppLanguage(rawValue: String(first.prefix(2))) else { return .system }
        return language
    }

    private static let overrideKey = "EasyShootLanguageOverride"

    func apply() {
        let defaults = UserDefaults.standard
        if self == .system {
            defaults.removeObject(forKey: "AppleLanguages")
            defaults.removeObject(forKey: Self.overrideKey)
        } else {
            defaults.set([rawValue], forKey: "AppleLanguages")
            defaults.set(rawValue, forKey: Self.overrideKey)
        }
    }
}
