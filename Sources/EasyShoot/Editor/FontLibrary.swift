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
    /// Families of the fonts this app registered. NSFontManager can list them a moment later than they work.
    private var registeredFamilies: Set<String> = []

    private var fontsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("EasyShoot/Fonts", isDirectory: true)
    }

    private init() {
        reloadInstalled()
    }

    func reloadInstalled() {
        let system = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }
        installedFamilies = Set(system).union(registeredFamilies)
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
            let families = files.filter { ["ttf", "otf"].contains($0.pathExtension.lowercased()) }.flatMap { register($0) }
            if !families.isEmpty { downloaded.insert(folder.lastPathComponent) }
        }
        reloadInstalled()
    }

    /// Registers a font file for this app and returns the families in it, also when it was registered before.
    private func register(_ file: URL) -> [String] {
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(file as CFURL, .process, &error) {
            let code = error.map { CFErrorGetCode($0.takeRetainedValue()) }
            guard code == CTFontManagerError.alreadyRegistered.rawValue else { return [] }
        }
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor] ?? []
        let families = descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String }
        registeredFamilies.formUnion(families)
        return families
    }

    /// Downloads the regular and bold styles of a Google Font family. Returns the family name to use, spelled
    /// as Google does ("rubik" → "Rubik"), or nil with `lastError` set.
    func download(_ family: String) async -> String? {
        let typed = family.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, !downloading.contains(typed) else { return nil }
        lastError = nil
        if isAvailable(typed) { return typed }
        downloading.insert(typed)
        defer { downloading.remove(typed) }

        guard let (name, urls) = await Self.findOnGoogle(typed) else {
            lastError = L("Couldn’t find “%@” on Google Fonts.", typed)
            return nil
        }
        if isAvailable(name) { return name }

        let folder = fontsDirectory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var families: [String] = []
        for (index, url) in urls.enumerated() {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            let ext = url.pathExtension.isEmpty ? "ttf" : url.pathExtension
            let file = folder.appendingPathComponent("\(name.replacingOccurrences(of: " ", with: ""))-\(index).\(ext)")
            guard (try? data.write(to: file, options: .atomic)) != nil else { continue }
            families += register(file)
        }
        guard !families.isEmpty else {
            lastError = L("Downloading “%@” failed. Check your internet connection.", name)
            return nil
        }
        downloaded.insert(name)
        reloadInstalled()
        // The files normally use Google's name; if a font calls itself something else, use what it says.
        return families.contains(name) ? name : families.min { $0.count < $1.count }
    }

    /// The family as Google spells it, with its font files. Google matches names case-sensitively, so a name
    /// that isn't found is tried again capitalized ("open sans"), then looked up in Google's catalog ("ibm plex sans").
    private nonisolated static func findOnGoogle(_ typed: String) async -> (name: String, urls: [URL])? {
        var candidates = [typed]
        let capitalized = typed.split(separator: " ").map { $0.prefix(1).uppercased() + String($0.dropFirst()) }.joined(separator: " ")
        if capitalized != typed { candidates.append(capitalized) }
        for name in candidates {
            let urls = await fontURLs(family: name)
            if !urls.isEmpty { return (name, urls) }
        }
        guard let name = await catalogName(matching: typed), !candidates.contains(name) else { return nil }
        let urls = await fontURLs(family: name)
        return urls.isEmpty ? nil : (name, urls)
    }

    /// The regular and bold files, or only the default style of a family that has neither weight.
    private nonisolated static func fontURLs(family: String) async -> [URL] {
        // The plain request also tells whether the family exists at all.
        var urls = await cssFontURLs(family: family, weights: "")
        guard !urls.isEmpty else { return [] }
        for weights in [":wght@400", ":wght@700"] {
            let more = await cssFontURLs(family: family, weights: weights)
            for url in more where !urls.contains(url) { urls.append(url) }
        }
        return urls
    }

    /// Google's CSS API returns TrueType URLs to clients it doesn't recognise as a browser.
    private nonisolated static func cssFontURLs(family: String, weights: String) async -> [URL] {
        let encoded = family.replacingOccurrences(of: " ", with: "+")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? family
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

    /// The exact spelling of a family in Google's font catalog, matched regardless of case.
    private nonisolated static func catalogName(matching typed: String) async -> String? {
        guard let url = URL(string: "https://fonts.google.com/metadata/fonts"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let catalog = try? JSONDecoder().decode(GoogleFontCatalog.self, from: data) else { return nil }
        return catalog.familyMetadataList.first { $0.family.caseInsensitiveCompare(typed) == .orderedSame }?.family
    }
}

private struct GoogleFontCatalog: Decodable {
    struct Family: Decodable { let family: String }
    let familyMetadataList: [Family]
}

extension AnnotationStyle {
    /// `fontName` in bold when it has a bold style, otherwise the system font.
    func font(size: CGFloat) -> NSFont {
        NSFont.family(fontName, size: size, bold: true) ?? NSFont.systemFont(ofSize: size, weight: .semibold)
    }
}

extension NSFont {
    /// A style of `family` (bold when asked and available, else regular), or the font with that PostScript name.
    /// Falls back to Core Text matching, which finds a font registered moments ago before NSFontManager lists it.
    static func family(_ family: String, size: CGFloat, bold: Bool) -> NSFont? {
        guard !family.isEmpty else { return nil }
        let manager = NSFontManager.shared
        if bold, let font = manager.font(withFamily: family, traits: .boldFontMask, weight: 9, size: size) { return font }
        if let font = manager.font(withFamily: family, traits: [], weight: 5, size: size) { return font }
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
        for candidate in bold ? [descriptor.withSymbolicTraits(.bold), descriptor] : [descriptor] {
            if let match = candidate.matchingFontDescriptor(withMandatoryKeys: [.family]),
               let font = NSFont(descriptor: match, size: size) { return font }
        }
        return NSFont(name: family, size: size)
    }
}
