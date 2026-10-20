import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var saveDirectoryPath: String { didSet { defaults.set(saveDirectoryPath, forKey: "saveDirectoryPath") } }
    @Published var showQuickAccess: Bool { didSet { defaults.set(showQuickAccess, forKey: "showQuickAccess") } }
    @Published var copyAfterCapture: Bool { didSet { defaults.set(copyAfterCapture, forKey: "copyAfterCapture") } }
    @Published var saveAfterCapture: Bool { didSet { defaults.set(saveAfterCapture, forKey: "saveAfterCapture") } }
    @Published var openEditorAfterCapture: Bool { didSet { defaults.set(openEditorAfterCapture, forKey: "openEditorAfterCapture") } }
    @Published var playSound: Bool { didSet { defaults.set(playSound, forKey: "playSound") } }
    /// Seconds before Quick Access closes itself; 0 keeps it open.
    @Published var quickAccessAutoClose: Double { didSet { defaults.set(quickAccessAutoClose, forKey: "quickAccessAutoClose") } }
    @Published var captureWindowShadow: Bool { didSet { defaults.set(captureWindowShadow, forKey: "captureWindowShadow") } }

    var saveDirectory: URL { URL(fileURLWithPath: (saveDirectoryPath as NSString).expandingTildeInPath, isDirectory: true) }

    private init() {
        defaults.register(defaults: [
            "saveDirectoryPath": "~/Desktop",
            "showQuickAccess": true,
            "copyAfterCapture": false,
            "saveAfterCapture": false,
            "openEditorAfterCapture": false,
            "playSound": true,
            "quickAccessAutoClose": 0.0,
            "captureWindowShadow": true,
        ])
        saveDirectoryPath = defaults.string(forKey: "saveDirectoryPath") ?? "~/Desktop"
        showQuickAccess = defaults.bool(forKey: "showQuickAccess")
        copyAfterCapture = defaults.bool(forKey: "copyAfterCapture")
        saveAfterCapture = defaults.bool(forKey: "saveAfterCapture")
        openEditorAfterCapture = defaults.bool(forKey: "openEditorAfterCapture")
        playSound = defaults.bool(forKey: "playSound")
        quickAccessAutoClose = defaults.double(forKey: "quickAccessAutoClose")
        captureWindowShadow = defaults.bool(forKey: "captureWindowShadow")
    }
}
