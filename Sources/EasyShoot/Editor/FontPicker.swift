import AppKit
import CoreText
import SwiftUI

/// Button that shows the current font and opens a searchable picker with every font on this Mac plus Google Fonts.
struct FontPickerButton: View {
    @Binding var fontName: String
    @ObservedObject var library = FontLibrary.shared
    @State private var open = false

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(fontName.isEmpty ? L("System") : fontName)
                    .font(previewFont(fontName, size: 13))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            FontPickerView(fontName: $fontName, library: library) { open = false }
        }
    }
}

/// The family as the canvas finds it, so a font downloaded moments ago shows in its own style straight away.
func previewFont(_ family: String, size: CGFloat) -> Font {
    guard let font = NSFont.family(family, size: size, bold: false) else { return .system(size: size, weight: .semibold) }
    return Font(font as CTFont)
}

struct FontPickerView: View {
    @Binding var fontName: String
    @ObservedObject var library: FontLibrary
    var dismiss: () -> Void

    @State private var tab: Tab = .mac
    @State private var query = ""
    @State private var googleName = ""
    @FocusState private var searchFocused: Bool

    enum Tab: Hashable { case mac, google }

    private static let arabicFamilies: Set<String> = [
        "Geeza Pro", "Al Nile", "Baghdad", "DecoType Naskh", "Diwan Kufi", "Diwan Thuluth", "Farah", "Farisi",
        "KufiStandardGK", "Mishafi", "Nadeem", "Noto Nastaliq Urdu", "Sana", "SF Arabic", "Waseem", "Al Bayan",
        "Al Tarikh", "Damascus", "Muna",
    ]

    var body: some View {
        VStack(spacing: 0) {
            Picker(L("Font"), selection: $tab) {
                Text(L("On This Mac")).tag(Tab.mac)
                Text(L("Google Fonts")).tag(Tab.google)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top], 12)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Search fonts"), text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain)
                        .help(L("Clear search"))
                        .accessibilityLabel(L("Clear search"))
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            .padding(12)

            Divider()

            switch tab {
            case .mac: macList
            case .google: googleList
            }
        }
        .frame(width: 320, height: 440)
        // Type to search straight away when the picker opens.
        .onAppear { searchFocused = true }
    }

    // MARK: Installed

    private var filteredInstalled: [String] {
        let all = library.installedFamilies
        guard !query.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var macList: some View {
        List {
            if query.isEmpty {
                Section(L("Recommended")) {
                    row("", title: L("System"))
                    ForEach(["SF Pro Rounded", "Helvetica Neue", "Avenir Next", "Menlo"].filter(library.isAvailable), id: \.self) { row($0) }
                }
                let arabic = library.installedFamilies.filter { Self.arabicFamilies.contains($0) }
                if !arabic.isEmpty {
                    Section(L("Arabic")) {
                        ForEach(arabic, id: \.self) { row($0, sample: "أبجد هوز") }
                    }
                }
            }
            Section(L("All Fonts (%d)", filteredInstalled.count)) {
                ForEach(filteredInstalled, id: \.self) { row($0) }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ family: String, title: String? = nil, sample: String? = nil) -> some View {
        Button {
            fontName = family
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(sample ?? (title ?? family))
                        .font(previewFont(family, size: 15))
                        .lineLimit(1)
                    if sample != nil || title == nil {
                        Text(title ?? family).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if fontName == family {
                    Image(systemName: "checkmark").foregroundStyle(Brand.signal)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Google

    private var googleList: some View {
        VStack(spacing: 0) {
            List {
                Section(L("Popular")) {
                    ForEach(FontLibrary.featuredGoogleFonts.filter { query.isEmpty || $0.family.localizedCaseInsensitiveContains(query) }) { font in
                        googleRow(font.family, arabic: font.arabic)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Any Google Font")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField(L("Font name, e.g. Rubik"), text: $googleName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(downloadTyped)
                    Button(L("Download"), action: downloadTyped)
                        .disabled(googleName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let error = library.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Text(L("Fonts are downloaded once and stay on your Mac."))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(12)
        }
    }

    private func googleRow(_ family: String, arabic: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(arabic ? "أبجد هوز — \(family)" : family)
                    .font(library.isAvailable(family) ? previewFont(family, size: 15) : .system(size: 14))
                    .lineLimit(1)
                if arabic {
                    Text(L("Arabic")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if library.downloading.contains(family) {
                ProgressView().controlSize(.small)
            } else if library.isAvailable(family) {
                Button(fontName == family ? L("Selected") : L("Use")) {
                    fontName = family
                    dismiss()
                }
                .disabled(fontName == family)
            } else {
                Button {
                    Task {
                        if let name = await library.download(family) { fontName = name }
                    }
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
                .help(L("Download"))
            }
        }
    }

    private func downloadTyped() {
        let name = googleName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            if let family = await library.download(name) {
                fontName = family
                googleName = ""
            }
        }
    }
}
