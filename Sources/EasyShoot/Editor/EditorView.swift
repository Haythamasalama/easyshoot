import SwiftUI

struct EditorView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var presets: PresetStore

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(model: model)
            Divider()
            HStack(spacing: 0) {
                CanvasRepresentable(model: model)
                    .frame(minWidth: 480, minHeight: 360)
                    .overlay(alignment: .top) {
                        if model.isCropping { CropBar(model: model).padding(.top, 10) }
                    }
                Divider()
                InspectorView(model: model)
                    .frame(width: 280)
            }
            Divider()
            EditorBottomBar(model: model, presets: presets)
        }
    }
}

// MARK: - Toolbar

private struct ToolButtonStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.accentColor.opacity(0.18) : (configuration.isPressed ? Color.primary.opacity(0.1) : .clear))
            )
    }
}

struct EditorToolbar: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Tool.allCases) { tool in
                Button {
                    model.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 30, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ToolButtonStyle(selected: model.tool == tool))
                .help("\(tool.title) (\(String(tool.shortcut).uppercased()))")
            }

            Divider().frame(height: 20).padding(.horizontal, 6)

            ForEach(RGBAColor.palette, id: \.self) { color in
                Button {
                    var style = model.activeStyle
                    style.color = color
                    model.setActiveStyle(style)
                } label: {
                    Circle()
                        .fill(color.color)
                        .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: model.activeStyle.color == color ? 2 : 0).padding(-3))
                        .frame(width: 16, height: 16)
                        .padding(3)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!model.canUndo)
                .help("Undo (⌘Z)")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!model.canRedo)
                .help("Redo (⇧⌘Z)")
            Button { model.clearAnnotations() } label: { Image(systemName: "trash") }
                .disabled(model.doc.annotations.isEmpty)
                .help("Remove all annotations")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

struct CropBar: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 8) {
            Text("Crop").font(.headline)
            Menu("Aspect") {
                Button("Freeform") {}
                ForEach(AspectRatio.allCases.filter { $0 != .auto }) { ratio in
                    Button(ratio.title) { model.setCropAspect(ratio.value) }
                }
            }
            .fixedSize()
            Button("Reset") { model.resetCropDraft() }
            Button("Cancel") { model.cancelCrop() }
            Button("Apply") { model.applyCrop() }
                .buttonStyle(.borderedProminent)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 6)
    }
}

// MARK: - Inspector

struct InspectorView: View {
    @ObservedObject var model: EditorModel
    @State private var tab: Tab = .style

    enum Tab: String, CaseIterable {
        case style = "Style"
        case background = "Background"
        case export = "Export"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch tab {
                    case .style: StyleInspector(model: model)
                    case .background: BackgroundInspector(model: model)
                    case .export: ExportInspector(model: model)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

private struct LabeledSlider: View {
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
        VStack(alignment: .leading, spacing: 14) {
            if let selected = model.selectedAnnotation {
                HStack {
                    Text("Editing selected \(selected.kind.rawValue)").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.bringSelectedToFront() } label: { Image(systemName: "square.3.layers.3d.top.filled") }
                        .help("Bring to front")
                    Button(role: .destructive) { model.deleteSelected() } label: { Image(systemName: "trash") }
                        .help("Delete (⌫)")
                }
            }

            SectionTitle("Color")
            HStack {
                ColorPicker("Color", selection: color, supportsOpacity: true)
                Spacer()
                Toggle("Shadow", isOn: style.shadow)
            }

            SectionTitle("Stroke")
            LabeledSlider(title: "Thickness", value: style.lineWidth, range: 1...20)

            SectionTitle("Text & Counter")
            LabeledSlider(title: "Size", value: style.fontSize, range: 10...96)
            Picker("Font", selection: style.fontName) {
                ForEach(FontChoice.all) { Text($0.title).tag($0.name) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Style").font(.callout)
                Picker("Style", selection: style.textStyle) {
                    ForEach(TextStyleKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Direction").font(.callout)
                Picker("Direction", selection: style.textDirection) {
                    ForEach(TextDirection.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("Auto detects Arabic / Hebrew and writes right-to-left. اكتب بالعربي مباشرة.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SectionTitle("Shortcuts")
            Text("V select · C crop · A arrow · L line · R rect · F filled · O ellipse · T text · N counter · H highlight · P pen · B pixelate · ⇧ constrain · ⌫ delete")
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
        RoundedRectangle(cornerRadius: 6)
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
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Background", isOn: bg.enabled)
                .toggleStyle(.switch)
                .font(.headline)

            Group {
                SectionTitle("Fill")
                Picker("Fill", selection: bg.fill) {
                    ForEach(BackgroundFill.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch model.doc.background.fill {
                case .gradient:
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                        ForEach(GradientPreset.all.indices, id: \.self) { i in
                            GradientSwatch(colors: GradientPreset.all[i].colors, angle: GradientPreset.all[i].angle)
                                .frame(height: 34)
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.accentColor, lineWidth: model.doc.background.gradientIndex == i ? 2.5 : 0))
                                .onTapGesture { model.doc.background.gradientIndex = i }
                                .help(GradientPreset.all[i].name)
                        }
                    }
                case .solid:
                    ColorPicker("Color", selection: colorBinding(\.solidColor), supportsOpacity: false)
                case .custom:
                    ColorPicker("Start", selection: colorBinding(\.customStart), supportsOpacity: false)
                    ColorPicker("End", selection: colorBinding(\.customEnd), supportsOpacity: false)
                    LabeledSlider(title: "Angle",
                                  value: Binding(get: { CGFloat(model.doc.background.customAngle) },
                                                 set: { model.doc.background.customAngle = Double($0) }),
                                  range: 0...360) { "\(Int($0))°" }
                case .transparent:
                    Text("Transparent background — keeps padding and shadow. Export as PNG to keep transparency.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SectionTitle("Layout")
                LabeledSlider(title: "Padding", value: bg.padding, range: 0...240)
                LabeledSlider(title: "Corner radius", value: bg.cornerRadius, range: 0...48)
                LabeledSlider(title: "Shadow", value: bg.shadow, range: 0...100)
                LabeledSlider(title: "Shadow opacity", value: bg.shadowOpacity, range: 0...1) { "\(Int($0 * 100))%" }

                Picker("Aspect ratio", selection: bg.aspectRatio) {
                    ForEach(AspectRatio.allCases) { Text($0.title).tag($0) }
                }

                HStack(alignment: .top) {
                    Text("Alignment").font(.callout)
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
                                            .fill(model.doc.background.alignment == alignment ? Color.accentColor : Color.secondary.opacity(0.3))
                                            .frame(width: 24, height: 16)
                                    }
                                    .buttonStyle(.plain)
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
}

struct ExportInspector: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Format")
            Picker("Format", selection: $model.export.format) {
                ForEach(ExportFormat.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if model.export.format.supportsQuality {
                LabeledSlider(title: "Quality",
                              value: Binding(get: { CGFloat(model.export.quality) }, set: { model.export.quality = Double($0) }),
                              range: 0.1...1) { "\(Int($0 * 100))%" }
            }

            SectionTitle("Resize")
            Picker("Resize", selection: $model.export.resizeMode) {
                ForEach(ResizeMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch model.export.resizeMode {
            case .original:
                EmptyView()
            case .percent:
                LabeledSlider(title: "Scale",
                              value: Binding(get: { CGFloat(model.export.percent) }, set: { model.export.percent = Double($0).rounded() }),
                              range: 10...200) { "\(Int($0))%" }
            case .width:
                HStack {
                    Text("Width")
                    TextField("Width", value: $model.export.width, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Text("px").foregroundStyle(.secondary)
                }
            }

            let size = model.outputSize
            HStack {
                Image(systemName: "photo")
                Text("\(Int(size.width)) × \(Int(size.height)) px")
                    .monospacedDigit()
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Text("Everything is saved locally on your Mac. Nothing is uploaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                Button("Save Current Style as Preset…") {
                    presetName = ""
                    showingSavePreset = true
                }
            } label: {
                Label("Presets", systemImage: "wand.and.stars")
            }
            .fixedSize()

            if let message = model.statusMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            Spacer()

            Image(systemName: "hand.draw")
                .font(.system(size: 15))
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                .onDrag { model.dragItemProvider() }
                .help("Drag the final image into any app")

            Button { model.copyToClipboard() } label: { Label("Copy", systemImage: "doc.on.doc") }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy image (⇧⌘C)")
            Button { model.saveAs() } label: { Label("Save As…", systemImage: "square.and.arrow.down.on.square") }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button { model.saveQuick() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.2), value: model.statusMessage)
        .alert("Save Preset", isPresented: $showingSavePreset) {
            TextField("Preset name", text: $presetName)
            Button("Save") {
                presets.add(model.makePreset(named: presetName))
                model.flash("Preset saved")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the background, annotation style and export settings so every screenshot can match your brand.")
        }
    }
}
