import SwiftUI

struct EditorView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var presets: PresetStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZStack(alignment: .top) {
                    CanvasRepresentable(model: model)
                        .frame(minWidth: 480, minHeight: 360)
                    VStack(spacing: 8) {
                        FloatingToolbar(model: model)
                        if model.isCropping {
                            CropBar(model: model)
                        } else if model.showsTextBar {
                            TextBar(model: model)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.horizontal, 12)
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.showsTextBar)
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.isCropping)
                }
                Divider()
                InspectorView(model: model)
                    .frame(width: 290)
            }
            Divider()
            EditorBottomBar(model: model, presets: presets)
        }
    }
}

// MARK: - Floating toolbar

private struct ToolButtonStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Brand.signal : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Brand.signal.opacity(0.16) : (configuration.isPressed ? Color.primary.opacity(0.12) : .clear))
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct FloatingToolbar: View {
    @ObservedObject var model: EditorModel

    private let groups: [[Tool]] = [
        [.select, .crop],
        [.arrow, .line, .rectangle, .filledRectangle, .ellipse],
        [.text, .counter],
        [.highlighter, .pen, .pixelate],
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(groups.indices, id: \.self) { index in
                if index > 0 {
                    Divider().frame(height: 18).padding(.horizontal, 3)
                }
                ForEach(groups[index]) { tool in
                    Button {
                        model.tool = tool
                    } label: {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 32, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ToolButtonStyle(selected: model.tool == tool))
                    .help("\(tool.title)  \(String(tool.shortcut).uppercased())")
                }
            }

            Divider().frame(height: 18).padding(.horizontal, 3)

            ColorDots(model: model)

            Divider().frame(height: 18).padding(.horizontal, 3)

            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 26, height: 28) }
                .buttonStyle(ToolButtonStyle(selected: false))
                .disabled(!model.canUndo)
                .help(L("Undo") + "  ⌘Z")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 26, height: 28) }
                .buttonStyle(ToolButtonStyle(selected: false))
                .disabled(!model.canRedo)
                .help(L("Redo") + "  ⇧⌘Z")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .glassSurface(cornerRadius: 14)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

struct ColorDots: View {
    @ObservedObject var model: EditorModel
    @State private var showPicker = false

    private var colorBinding: Binding<Color> {
        Binding(get: { model.activeStyle.color.color },
                set: {
                    var style = model.activeStyle
                    style.color = RGBAColor(nsColor: NSColor($0))
                    model.setActiveStyle(style)
                })
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach([RGBAColor.red, .orange, .yellow, .green, .blue, .purple, .black, .white], id: \.self) { color in
                Button {
                    var style = model.activeStyle
                    style.color = color
                    model.setActiveStyle(style)
                } label: {
                    Circle()
                        .fill(color.color)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                        .frame(width: 15, height: 15)
                        .padding(3)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.85), lineWidth: model.activeStyle.color == color ? 2 : 0))
                }
                .buttonStyle(.plain)
            }
            ColorPicker("", selection: colorBinding, supportsOpacity: true)
                .labelsHidden()
                .frame(width: 26)
                .help(L("More colors"))
        }
    }
}

// MARK: - Text bar

/// Appears for the text tool or a selected text: font, size and background, one click away.
struct TextBar: View {
    @ObservedObject var model: EditorModel

    private var style: Binding<AnnotationStyle> {
        Binding(get: { model.activeStyle }, set: { model.setActiveStyle($0) })
    }

    var body: some View {
        HStack(spacing: 10) {
            FontPickerButton(fontName: style.fontName)
                .frame(width: 150)

            HStack(spacing: 0) {
                Button { model.adjustFontSize(by: -2) } label: {
                    Image(systemName: "textformat.size.smaller").frame(width: 28, height: 24)
                }
                .keyboardShortcut("-", modifiers: .command)
                .help(L("Smaller") + "  ⌘−")
                Text("\(Int(model.activeStyle.fontSize))")
                    .monospacedDigit()
                    .frame(minWidth: 26)
                Button { model.adjustFontSize(by: 2) } label: {
                    Image(systemName: "textformat.size.larger").frame(width: 28, height: 24)
                }
                .keyboardShortcut("=", modifiers: .command)
                .help(L("Bigger") + "  ⌘+")
            }
            .buttonStyle(ToolButtonStyle(selected: false))

            Picker("", selection: style.textStyle) {
                Image(systemName: "character").help(L("Plain")).tag(TextStyleKind.plain)
                Image(systemName: "character.textbox").help(L("Bubble")).tag(TextStyleKind.background)
                Image(systemName: "a.circle").help(L("Outline")).tag(TextStyleKind.outline)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 110)

            Picker("", selection: style.textDirection) {
                Text(L("Auto")).tag(TextDirection.auto)
                Image(systemName: "text.alignleft").help(L("Left to right")).tag(TextDirection.ltr)
                Image(systemName: "text.alignright").help(L("Right to left")).tag(TextDirection.rtl)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 120)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassSurface(cornerRadius: 12)
        .shadow(color: .black.opacity(0.1), radius: 10, y: 3)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct CropBar: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "crop").foregroundStyle(Brand.signal)
            Menu(L("Aspect")) {
                Button(L("Freeform")) {}
                ForEach(AspectRatio.allCases.filter { $0 != .auto }) { ratio in
                    Button(ratio.title) { model.setCropAspect(ratio.value) }
                }
            }
            .fixedSize()
            Button(L("Reset")) { model.resetCropDraft() }
            Button(L("Cancel")) { model.cancelCrop() }
            Button(L("Apply")) { model.applyCrop() }
                .primaryButtonStyle()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassSurface(cornerRadius: 12)
        .shadow(color: .black.opacity(0.1), radius: 10, y: 3)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Inspector

struct InspectorView: View {
    @ObservedObject var model: EditorModel
    @State private var tab: Tab = .style

    enum Tab: CaseIterable {
        case style, background, export

        var title: String {
            switch self {
            case .style: return L("Style")
            case .background: return L("Background")
            case .export: return L("Export")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case .style: StyleInspector(model: model)
                    case .background: BackgroundInspector(model: model)
                    case .export: ExportInspector(model: model)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.background.secondary)
    }
}

/// A rounded group with a small caption, like the grouped sections in System Settings.
struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.background))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    var format: (CGFloat) -> String = { "\(Int($0))" }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }
}

struct StyleInspector: View {
    @ObservedObject var model: EditorModel

    private var style: Binding<AnnotationStyle> {
        Binding(get: { model.activeStyle }, set: { model.setActiveStyle($0) })
    }

    private var color: Binding<Color> {
        Binding(get: { model.activeStyle.color.color },
                set: { style.wrappedValue.color = RGBAColor(nsColor: NSColor($0)) })
    }

    var body: some View {
        if model.selectedAnnotation != nil {
            HStack {
                Label(L("Selection"), systemImage: "cursorarrow.click.2")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { model.bringSelectedToFront() } label: { Image(systemName: "square.3.layers.3d.top.filled") }
                    .buttonStyle(.borderless)
                    .help(L("Bring to front"))
                Button(role: .destructive) { model.deleteSelected() } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help(L("Delete") + "  ⌫")
            }
            .padding(.horizontal, 4)
        }

        InspectorSection(title: L("Color")) {
            HStack {
                ColorPicker(L("Color"), selection: color, supportsOpacity: true)
                Spacer()
                Toggle(L("Shadow"), isOn: style.shadow)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        }

        InspectorSection(title: L("Stroke")) {
            LabeledSlider(title: L("Thickness"), value: style.lineWidth, range: 1...20)
        }

        InspectorSection(title: L("Text & Counter")) {
            HStack {
                Text(L("Font"))
                Spacer()
                FontPickerButton(fontName: style.fontName)
                    .frame(width: 150)
            }
            HStack {
                Text(L("Size"))
                Spacer()
                Stepper(value: style.fontSize, in: 8...200, step: 2) {
                    Text("\(Int(model.activeStyle.fontSize))").monospacedDigit()
                }
            }
            Slider(value: style.fontSize, in: 8...160)
                .controlSize(.small)
            Picker(L("Background"), selection: style.textStyle) {
                ForEach(TextStyleKind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker(L("Direction"), selection: style.textDirection) {
                ForEach(TextDirection.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(L("Auto detects Arabic and Hebrew and writes right-to-left. Drag the corner of a selected text to resize it."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct GradientSwatch: View {
    let colors: [RGBAColor]
    let angle: Double

    var body: some View {
        let rad = angle * .pi / 180
        let dx = cos(rad) / 2, dy = sin(rad) / 2
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(LinearGradient(colors: colors.map(\.color),
                                 startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                                 endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)))
    }
}

struct BackgroundInspector: View {
    @ObservedObject var model: EditorModel

    private var bg: Binding<BackgroundSettings> { $model.doc.background }

    private func colorBinding(_ keyPath: WritableKeyPath<BackgroundSettings, RGBAColor>) -> Binding<Color> {
        Binding(get: { model.doc.background[keyPath: keyPath].color },
                set: { model.doc.background[keyPath: keyPath] = RGBAColor(nsColor: NSColor($0)) })
    }

    var body: some View {
        InspectorSection(title: L("Background")) {
            Toggle(L("Show background"), isOn: bg.enabled)
                .toggleStyle(.switch)
        }

        Group {
            InspectorSection(title: L("Fill")) {
                Picker("", selection: bg.fill) {
                    ForEach(BackgroundFill.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch model.doc.background.fill {
                case .gradient:
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                        ForEach(GradientPreset.all.indices, id: \.self) { i in
                            GradientSwatch(colors: GradientPreset.all[i].colors, angle: GradientPreset.all[i].angle)
                                .frame(height: 32)
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.85), lineWidth: model.doc.background.gradientIndex == i ? 2.5 : 0))
                                .onTapGesture { model.doc.background.gradientIndex = i }
                                .help(GradientPreset.all[i].name)
                        }
                    }
                case .solid:
                    ColorPicker(L("Color"), selection: colorBinding(\.solidColor), supportsOpacity: false)
                case .custom:
                    ColorPicker(L("Start"), selection: colorBinding(\.customStart), supportsOpacity: false)
                    ColorPicker(L("End"), selection: colorBinding(\.customEnd), supportsOpacity: false)
                    LabeledSlider(title: L("Angle"),
                                  value: Binding(get: { CGFloat(model.doc.background.customAngle) },
                                                 set: { model.doc.background.customAngle = Double($0) }),
                                  range: 0...360) { "\(Int($0))°" }
                case .transparent:
                    Text(L("Transparent background: keeps padding and shadow. Export as PNG to keep transparency."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            InspectorSection(title: L("Layout")) {
                LabeledSlider(title: L("Padding"), value: bg.padding, range: 0...240)
                LabeledSlider(title: L("Corner radius"), value: bg.cornerRadius, range: 0...48)
                LabeledSlider(title: L("Shadow"), value: bg.shadow, range: 0...100)
                LabeledSlider(title: L("Shadow opacity"), value: bg.shadowOpacity, range: 0...1) { "\(Int($0 * 100))%" }
                Picker(L("Aspect ratio"), selection: bg.aspectRatio) {
                    ForEach(AspectRatio.allCases) { Text($0.title).tag($0) }
                }
                HStack(alignment: .top) {
                    Text(L("Alignment")).font(.callout)
                    Spacer()
                    Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                        ForEach(0..<3, id: \.self) { row in
                            GridRow {
                                ForEach(0..<3, id: \.self) { col in
                                    let alignment = ContentAlignment.allCases[row * 3 + col]
                                    Button {
                                        model.doc.background.alignment = alignment
                                    } label: {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(model.doc.background.alignment == alignment ? Color.accentColor : Color.secondary.opacity(0.25))
                                            .frame(width: 24, height: 16)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
        .disabled(!model.doc.background.enabled)
        .opacity(model.doc.background.enabled ? 1 : 0.45)
    }
}

struct ExportInspector: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        InspectorSection(title: L("Format")) {
            Picker("", selection: $model.export.format) {
                ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if model.export.format.supportsQuality {
                LabeledSlider(title: L("Quality"),
                              value: Binding(get: { CGFloat(model.export.quality) }, set: { model.export.quality = Double($0) }),
                              range: 0.1...1) { "\(Int($0 * 100))%" }
            }
        }

        InspectorSection(title: L("Resize")) {
            Picker("", selection: $model.export.resizeMode) {
                ForEach(ResizeMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch model.export.resizeMode {
            case .original:
                EmptyView()
            case .percent:
                LabeledSlider(title: L("Scale"),
                              value: Binding(get: { CGFloat(model.export.percent) }, set: { model.export.percent = Double($0).rounded() }),
                              range: 10...200) { "\(Int($0))%" }
            case .width:
                HStack {
                    Text(L("Width"))
                    TextField("", value: $model.export.width, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Text("px").foregroundStyle(.secondary)
                }
            }

            let size = model.outputSize
            Label("\(Int(size.width)) × \(Int(size.height)) px", systemImage: "photo")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }

        Label(L("Everything is saved locally on your Mac. Nothing is uploaded."), systemImage: "lock.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Bottom bar

struct EditorBottomBar: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var presets: PresetStore
    @State private var showingSavePreset = false
    @State private var presetName = ""

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(presets.presets) { preset in
                    Button(preset.name) { model.apply(preset) }
                }
                Divider()
                Button(L("Save Current Style as Preset…")) {
                    presetName = ""
                    showingSavePreset = true
                }
            } label: {
                Label(L("Presets"), systemImage: "wand.and.stars")
            }
            .fixedSize()

            if let message = model.statusMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            Spacer()

            Image(systemName: "hand.draw")
                .font(.system(size: 14))
                .frame(width: 30, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.07)))
                .onDrag { model.dragItemProvider() }
                .help(L("Drag the final image into any app"))

            Button { model.copyToClipboard() } label: { Label(L("Copy"), systemImage: "doc.on.doc") }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .secondaryButtonStyle()
                .help(L("Copy image") + "  ⇧⌘C")
            Button { model.saveAs() } label: { Label(L("Save As…"), systemImage: "square.and.arrow.down.on.square") }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .secondaryButtonStyle()
            Button { model.saveQuick() } label: { Label(L("Save"), systemImage: "square.and.arrow.down") }
                .keyboardShortcut("s", modifiers: .command)
                .primaryButtonStyle()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .animation(.easeInOut(duration: 0.2), value: model.statusMessage)
        .alert(L("Save Preset"), isPresented: $showingSavePreset) {
            TextField(L("Preset name"), text: $presetName)
            Button(L("Save")) {
                presets.add(model.makePreset(named: presetName))
                model.flash(L("Preset saved"))
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Saves the background, annotation style and export settings so every screenshot can match your brand."))
        }
    }
}
