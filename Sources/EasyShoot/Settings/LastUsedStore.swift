import Foundation

/// The editor settings from the last screenshot, so the next one starts the same way.
/// Used when no default preset is set.
struct LastUsed: Codable, Equatable {
    var background: BackgroundSettings
    var style: AnnotationStyle
    var export: ExportOptions
    var tool: String
}

enum LastUsedStore {
    private static let key = "lastUsedEditorSettings"

    static func load(from defaults: UserDefaults = .standard) -> LastUsed? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LastUsed.self, from: data)
    }

    static func save(_ value: LastUsed, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
