import Foundation

@MainActor
final class PresetStore: ObservableObject {
    static let shared = PresetStore()

    @Published var presets: [Preset] {
        didSet { save() }
    }

    /// Preset applied automatically to every new capture.
    @Published var defaultPresetID: UUID? {
        didSet { UserDefaults.standard.set(defaultPresetID?.uuidString, forKey: Self.defaultKey) }
    }

    private static let defaultKey = "defaultPresetID"

    var defaultPreset: Preset? {
        guard let id = defaultPresetID else { return nil }
        return presets.first { $0.id == id }
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("EasyShoot", isDirectory: true).appendingPathComponent("presets.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([Preset].self, from: data) {
            presets = decoded
        } else {
            presets = Preset.builtIns
        }
        if let raw = UserDefaults.standard.string(forKey: Self.defaultKey) {
            defaultPresetID = UUID(uuidString: raw)
        }
    }

    func add(_ preset: Preset) {
        presets.append(preset)
    }

    func remove(_ id: UUID) {
        presets.removeAll { $0.id == id }
        if defaultPresetID == id { defaultPresetID = nil }
    }

    func restoreBuiltIns() {
        let existing = Set(presets.map(\.name))
        presets.append(contentsOf: Preset.builtIns.filter { !existing.contains($0.name) })
    }

    private func save() {
        do {
            let url = Self.fileURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(presets).write(to: url, options: .atomic)
        } catch {
            NSLog("EasyShoot: failed to save presets: \(error)")
        }
    }
}
