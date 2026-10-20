import AppKit
import CoreText

/// Every font family installed on this Mac, plus Google Fonts that can be downloaded on demand.
/// Downloaded fonts are kept in ~/Library/Application Support/EasyShoot/Fonts and registered for this app only.
@MainActor
final class FontLibrary: ObservableObject {
    static let shared = FontLibrary()

    struct GoogleFont: Identifiable, Hashable {
        let family: String
        let arabic: Bool
        var id: String { family }
    }

    /// Curated, popular Google Fonts. Any other family can be typed by name.
    static let featuredGoogleFonts: [GoogleFont] = [
        GoogleFont(family: "Cairo", arabic: true),
        GoogleFont(family: "Tajawal", arabic: true),
        GoogleFont(family: "Almarai", arabic: true),
        GoogleFont(family: "IBM Plex Sans Arabic", arabic: true),
        GoogleFont(family: "Readex Pro", arabic: true),
        GoogleFont(family: "Noto Kufi Arabic", arabic: true),
        GoogleFont(family: "Changa", arabic: true),
        GoogleFont(family: "Amiri", arabic: true),
        GoogleFont(family: "El Messiri", arabic: true),
        GoogleFont(family: "Lalezar", arabic: true),
        GoogleFont(family: "Inter", arabic: false),
        GoogleFont(family: "Poppins", arabic: false),
        GoogleFont(family: "Montserrat", arabic: false),
        GoogleFont(family: "Roboto", arabic: false),
        GoogleFont(family: "Open Sans", arabic: false),
        GoogleFont(family: "Lato", arabic: false),
        GoogleFont(family: "Nunito", arabic: false),
        GoogleFont(family: "Work Sans", arabic: false),
        GoogleFont(family: "Space Grotesk", arabic: false),
        GoogleFont(family: "DM Sans", arabic: false),
        GoogleFont(family: "Playfair Display", arabic: false),
        GoogleFont(family: "Bebas Neue", arabic: false),
        GoogleFont(family: "JetBrains Mono", arabic: false),
        GoogleFont(family: "Caveat", arabic: false),
        GoogleFont(family: "Permanent Marker", arabic: false),
    ]

    @Published private(set) var installedFamilies: [String] = []
    @Published private(set) var downloading: Set<String> = []
    @Published private(set) var downloaded: Set<String> = []
    @Published var lastError: String?

    private var fontsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("EasyShoot/Fonts", isDirectory: true)
    }

    private init() {
        reloadInstalled()
    }

    func reloadInstalled() {
        installedFamilies = NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func isAvailable(_ family: String) -> Bool {
        installedFamilies.contains(family)
    }

    /// Registers fonts downloaded in earlier sessions.
    func registerDownloadedFonts() {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: fontsDirectory, includingPropertiesForKeys: nil) else { return }
        for folder in folders {
            let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where ["ttf", "otf"].contains(file.pathExtension.lowercased()) {
                CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
            }
            downloaded.insert(folder.lastPathComponent)
        }
        reloadInstalled()
    }

    /// Downloads the regular and bold styles of a Google Font family.
    func download(_ family: String) async -> Bool {
        let name = family.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !downloading.contains(name) else { return false }
        downloading.insert(name)
        defer { downloading.remove(name) }
        lastError = nil

        var fontURLs: [URL] = []
        for weights in [":wght@400", ":wght@700", ""] {
            let urls = await Self.cssFontURLs(family: name, weights: weights)
            fontURLs.append(contentsOf: urls)
            if !urls.isEmpty && weights.isEmpty { break }
        }
        let unique = Array(Set(fontURLs))
        guard !unique.isEmpty else {
            lastError = L("Couldn’t find “%@” on Google Fonts.", name)
            return false
        }

        let folder = fontsDirectory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var registered = 0
        for (index, url) in unique.enumerated() {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            let ext = url.pathExtension.isEmpty ? "ttf" : url.pathExtension
            let file = folder.appendingPathComponent("\(name.replacingOccurrences(of: " ", with: ""))-\(index).\(ext)")
            guard (try? data.write(to: file, options: .atomic)) != nil else { continue }
            if CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil) { registered += 1 }
        }
        guard registered > 0 else {
            lastError = L("Downloading “%@” failed. Check your internet connection.", name)
            return false
        }
        downloaded.insert(name)
        reloadInstalled()
        return true
    }

    /// Google's CSS API returns TrueType URLs to clients it doesn't recognise as a browser.
    private static func cssFontURLs(family: String, weights: String) async -> [URL] {
        let encoded = family.replacingOccurrences(of: " ", with: "+")
        guard let url = URL(string: "https://fonts.googleapis.com/css2?family=\(encoded)\(weights)") else { return [] }
        var request = URLRequest(url: url)
        request.setValue("EasyShoot/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let css = String(data: data, encoding: .utf8) else { return [] }
        var result: [URL] = []
        var rest = css[...]
        while let start = rest.range(of: "url(") {
            let after = rest[start.upperBound...]
            guard let end = after.firstIndex(of: ")") else { break }
            let raw = after[..<end].trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
            if let u = URL(string: raw) { result.append(u) }
            rest = after[end...]
        }
        return result
    }
}

extension AnnotationStyle {
    /// Resolves `fontName` as a family name (bold when available), falling back to a PostScript name, then the system font.
    func font(size: CGFloat) -> NSFont {
        if !fontName.isEmpty {
            let manager = NSFontManager.shared
            if let bold = manager.font(withFamily: fontName, traits: .boldFontMask, weight: 9, size: size) { return bold }
            if let regular = manager.font(withFamily: fontName, traits: [], weight: 5, size: size) { return regular }
            if let named = NSFont(name: fontName, size: size) { return named }
        }
        return NSFont.systemFont(ofSize: size, weight: .semibold)
    }
}
