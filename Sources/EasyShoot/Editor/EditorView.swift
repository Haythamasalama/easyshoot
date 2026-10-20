import SwiftUI

struct EditorView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var presets: PresetStore
    /// Hidden on small screens to give the canvas the whole window.
    @AppStorage("showInspector") private var showInspector = true

    private let inspectorTab: InspectorView.Tab

    /// The inspector opens at this width. People can drag its edge within `inspectorWidthRange`;
    /// its content adapts to the column, never the other way round.
    static let inspectorWidth: CGFloat = 290
    /// Narrower squeezes the labels; wider takes too much from the canvas on a 13-inch screen.
    static let inspectorWidthRange: ClosedRange<CGFloat> = 260...440
    static let canvasMinWidth: CGFloat = 400

    init(model: EditorModel, presets: PresetStore, inspectorTab: InspectorView.Tab = .style) {
        self.model = model
        self.presets = presets
        self.inspectorTab = inspectorTab
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                CanvasRepresentable(model: model)
                    .frame(minWidth: Self.canvasMinWidth, minHeight: 320)
                    .layoutProbe("canvas")
                VStack(spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        FloatingToolbar(model: model)
                        FloatingToolbar(model: model, compact: true)
                        FloatingToolbar(model: model, compact: true, foldsShapes: true)
                    }
                    .layoutProbe("toolbar")
                    if model.isCropping {
                        CropBar(model: model)
                    } else if model.showsTextBar {
                        ViewThatFits(in: .horizontal) {
                            TextBar(model: model)
                            TextBar(model: model, compact: true)
                        }
                        .layoutProbe("textBar")
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 12)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.showsTextBar)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: model.isCropping)
            }
            // The system inspector column: drag its edge to resize it (with the column-resize
            // pointer) within safe limits. It follows AppKit's layout direction, so it moves to the
            // left when the app runs in Arabic.
            .inspector(isPresented: $showInspector) {
                InspectorView(model: model, tab: inspectorTab)
                    .layoutProbe("inspector")
                    .inspectorColumnWidth(min: Self.inspectorWidthRange.lowerBound,
                                          ideal: Self.inspectorWidth,
                                          max: Self.inspectorWidthRange.upperBound)
            }
            Divider()
            EditorBottomBar(model: model, presets: presets, showInspector: $showInspector)
                .layoutProbe("bottomBar")
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
    /// Folds the colour row into one swatch with a popover, for narrow windows.
    var compact = false
    /// Also folds the five shapes into one menu, for the narrowest canvas (a wide inspector in a small window).
    var foldsShapes = false
    @State private var showColors = false

    private static let shapes: [Tool] = [.arrow, .line, .rectangle, .filledRectangle, .ellipse]
    private static let groups: [[Tool]] = [
        [.select, .crop],
        FloatingToolbar.shapes,
        [.text, .counter],
        [.highlighter, .pen, .pixelate],
    ]

    private var spacing: CGFloat { compact ? 2 : 4 }
    private var toolWidth: CGFloat { compact ? 27 : 32 }
    private var dividerPadding: CGFloat { compact ? 1 : 3 }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Self.groups, id: \.self) { group in
                HStack(spacing: spacing) {
                    if group != Self.groups.first {
                        divider
                    }
                    if foldsShapes && group == Self.shapes {
                        shapesMenu
                    } else {
                        ForEach(group) { tool in toolButton(tool) }
                    }
                }
            }

            divider

            if compact {
                Button { showColors.toggle() } label: {
                    Circle()
                        .fill(model.activeStyle.color.color)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                        .frame(width: 18, height: 18)
                        .frame(width: 30, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ToolButtonStyle(selected: false))
                .help(L("Color"))
                .popover(isPresented: $showColors, arrowEdge: .bottom) {
                    ColorDots(model: model).padding(10)
                }
            } else {
                ColorDots(model: model)
            }

            divider

            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 26, height: 28) }
                .buttonStyle(ToolButtonStyle(selected: false))
                .disabled(!model.canUndo)
                .help(L("Undo") + "  ⌘Z")
                .accessibilityLabel(L("Undo"))
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 26, height: 28) }
                .buttonStyle(ToolButtonStyle(selected: false))
                .disabled(!model.canRedo)
                .help(L("Redo") + "  ⇧⌘Z")
                .accessibilityLabel(L("Redo"))
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, 6)
        .glassSurface(cornerRadius: 14)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private var divider: some View {
        Divider().frame(height: 18).padding(.horizontal, dividerPadding)
    }

    private func toolButton(_ tool: Tool) -> some View {
        Button {
            model.tool = tool
        } label: {
            Image(systemName: tool.symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: toolWidth, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(ToolButtonStyle(selected: model.tool == tool))
        .help("\(tool.title)  \(String(tool.shortcut).uppercased())")
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(model.tool == tool ? .isSelected : [])
    }

    /// One button for all five shapes: it shows the current shape (or the arrow) and opens a menu of the others.
    private var shapesMenu: some View {
        let isShape = Self.shapes.contains(model.tool)
        return Menu {
            ForEach(Self.shapes) { tool in
                let title = tool.title + "  " + String(tool.shortcut).uppercased()
                Button {
                    model.tool = tool
                } label: {
                    Label(title, systemImage: tool.symbol)
                }
            }
        } label: {
            Image(systemName: (isShape ? model.tool : .arrow).symbol)
                .font(.system(size: 14, weight: .medium))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .padding(.horizontal, 4)
        .frame(height: 28)
        .foregroundStyle(isShape ? Brand.signal : Color.primary)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isShape ? Brand.signal.opacity(0.16) : .clear))
        .help(L("Shapes"))
        .accessibilityLabel(L("Shapes"))
    }
}

struct ColorDots: View {
    @ObservedObject var model: EditorModel
    @State private var showPicker = false

    private static let palette: [RGBAColor] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]
    private static let names: [RGBAColor: String] = [
        .red: L("Red"), .orange: L("Orange"), .yellow: L("Yellow"), .green: L("Green"),
        .blue: L("Blue"), .purple: L("Purple"), .black: L("Black"), .white: L("White"),
    ]

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
            ForEach(Self.palette, id: \.self) { color in
                let name = Self.names[color] ?? L("Color")
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
                .help(name)
                .accessibilityLabel(name)
                .accessibilityAddTraits(model.activeStyle.color == color ? .isSelected : [])
            }
            ColorWellButton(color: colorBinding, rainbow: true, size: 15, label: L("More colors"))
                .help(L("More colors"))
        }
    }
}

// MARK: - Text bar

/// Appears for the text tool or a selected text: font, size and background, one click away.
struct TextBar: View {
    @ObservedObject var model: EditorModel
    /// Drops the direction picker and narrows the font menu, for narrow windows.
    var compact = false

    private var style: Binding<AnnotationStyle> {
        Binding(get: { model.activeStyle }, set: { model.setActiveStyle($0) })
    }

    var body: some View {
        HStack(spacing: 10) {
            FontPickerButton(fontName: style.fontName)
                .frame(width: compact ? 110 : 150)

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

            Picker(L("Text style"), selection: style.textStyle) {
                Image(systemName: "character").help(L("Plain")).accessibilityLabel(L("Plain")).tag(TextStyleKind.plain)
                Image(systemName: "character.textbox").help(L("Bubble")).accessibilityLabel(L("Bubble")).tag(TextStyleKind.background)
                Image(systemName: "a.circle").help(L("Outline")).accessibilityLabel(L("Outline")).tag(TextStyleKind.outline)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 110)

            if !compact {
                Picker(L("Direction"), selection: style.textDirection) {
                    Text(L("Auto")).tag(TextDirection.auto)
                    Image(systemName: "text.alignleft").help(L("Left to right")).accessibilityLabel(L("Left to right")).tag(TextDirection.ltr)
                    Image(systemName: "text.alignright").help(L("Right to left")).accessibilityLabel(L("Right to left")).tag(TextDirection.rtl)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
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
            Image(systemName: "crop").foregroundStyle(Brand.signal).accessibilityHidden(true)
            // Long translations of "Aspect" and "Reset" turn into icons when the canvas is narrow.
            ViewThatFits(in: .horizontal) {
                cropOptions(iconsOnly: false)
                cropOptions(iconsOnly: true)
            }
            Button(L("Cancel")) { model.cancelCrop() }
                .help(L("Cancel") + "  esc")
            Button(L("Apply")) { model.applyCrop() }
                .primaryButtonStyle()
                .help(L("Apply") + "  ↩")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassSurface(cornerRadius: 12)
        .shadow(color: .black.opacity(0.1), radius: 10, y: 3)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func cropOptions(iconsOnly: Bool) -> some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(AspectRatio.allCases.filter { $0 != .auto }) { ratio in
                    Button(ratio.title) { model.setCropAspect(ratio.value) }
                }
            } label: {
                if iconsOnly { Image(systemName: "aspectratio") } else { Text(L("Aspect")) }
            }
            .fixedSize()
            .help(L("Aspect"))
            .accessibilityLabel(L("Aspect"))
            Button { model.resetCropDraft() } label: {
                if iconsOnly { Image(systemName: "arrow.counterclockwise") } else { Text(L("Reset")) }
            }
            .help(L("Reset"))
            .accessibilityLabel(L("Reset"))
        }
    }
}

// MARK: - Inspector

struct InspectorView: View {
    @ObservedObject var model: EditorModel
    /// Seeds the first tab once; after that the tab is the inspector's own state.
    @State private var tab: Tab

    init(model: EditorModel, tab: Tab = .style) {
        self.model = model
        _tab = State(initialValue: tab)
    }

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
            FittingSegments(selection: $tab, options: Tab.allCases.map { ($0, $0.title) })
                .layoutProbe("inspectorTabs")
                .padding(12)

            // The content takes the scroll view's width (the column minus an always-shown scroll bar),
            // whatever the person dragged the column to; clipping keeps any row inside it.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case .style: StyleInspector(model: model)
                    case .background: BackgroundInspector(model: model)
                    case .export: ExportInspector(model: model)
                    }
                }
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutProbe("inspectorContent")
                .padding(.horizontal, 12)
            }
        }
        .clipped()
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
                Text(title).lineLimit(1)
                Spacer(minLength: 8)
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary).fixedSize()
            }
            .font(.callout)
            Slider(value: $value, in: range) { Text(title) }
                .labelsHidden()
                .controlSize(.small)
                .accessibilityValue(format(value))
        }
    }
}

/// A caption above a control, for rows too narrow to hold both side by side.
struct LabeledRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.callout)
            content
        }
    }
}

struct ColorRow: View {
    let title: String
    @Binding var color: Color

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            ColorWellButton(color: $color, supportsOpacity: false, size: 22, label: title)
        }
    }
}

/// A segmented control whose segments share the width and shrink their labels,
/// so it never overflows a narrow panel or a longer translation.
struct FittingSegments<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.map { $0.0 }, id: \.self) { value in
                let title = options.first { $0.0 == value }?.1 ?? ""
                let selected = value == selection
                Button { selection = value } label: {
                    Text(title)
                        .font(.callout.weight(selected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Color.primary.opacity(0.13) : .clear)
                )
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

/// A round colour well that opens the system colour panel. SwiftUI's ColorPicker
/// draws a wide capsule on macOS 26, which breaks tight rows like the toolbar.
struct ColorWellButton: View {
    @Binding var color: Color
    var supportsOpacity = true
    var rainbow = false
    var size: CGFloat = 20
    /// What VoiceOver reads for this well.
    var label = L("Color")

    var body: some View {
        Button {
            ColorPanelBridge.shared.open(color: NSColor(color), showsAlpha: supportsOpacity) { color = Color(nsColor: $0) }
        } label: {
            Circle()
                .fill(rainbow
                      ? AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                      : AnyShapeStyle(color))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                .frame(width: size, height: size)
                .padding(3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The target of the app-wide colour panel. It is a single object that lives as long as the app, because
/// the panel outlives the colour wells that open it (a tab switch or a closed popover removes them).
@MainActor
final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()
    private var onChange: ((NSColor) -> Void)?

    /// Stops editing (for example when the editor window closes) and puts the panel away.
    func detach() {
        guard onChange != nil else { return }
        onChange = nil
        if NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.orderOut(nil) }
    }

    func open(color: NSColor, showsAlpha: Bool, onChange: @escaping (NSColor) -> Void) {
        let panel = NSColorPanel.shared
        panel.showsAlpha = showsAlpha
        panel.setTarget(nil)
        panel.color = color
        self.onChange = onChange
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        onChange?(sender.color)
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
                    .accessibilityLabel(L("Bring to front"))
                Button(role: .destructive) { model.deleteSelected() } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help(L("Delete") + "  ⌫")
                    .accessibilityLabel(L("Delete"))
            }
            .padding(.horizontal, 4)
        }

        InspectorSection(title: L("Color")) {
            HStack {
                Text(L("Color"))
                ColorWellButton(color: color)
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
                    .frame(maxWidth: 150)
            }
            HStack {
                Text(L("Size"))
                Spacer()
                Stepper(value: style.fontSize, in: 8...200, step: 2) {
                    Text("\(Int(model.activeStyle.fontSize))").monospacedDigit()
                }
            }
            Slider(value: style.fontSize, in: 8...200) { Text(L("Size")) }
                .labelsHidden()
                .controlSize(.small)
            LabeledRow(title: L("Background")) {
                FittingSegments(selection: style.textStyle, options: TextStyleKind.allCases.map { ($0, $0.title) })
            }
            LabeledRow(title: L("Direction")) {
                FittingSegments(selection: style.textDirection, options: TextDirection.allCases.map { ($0, $0.title) })
            }
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
                // A pop-up menu fits any inspector width and any translation, unlike four segments.
                Picker(L("Fill"), selection: bg.fill) {
                    ForEach(BackgroundFill.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                switch model.doc.background.fill {
                case .gradient:
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                        ForEach(GradientPreset.all) { preset in
                            let index = GradientPreset.all.firstIndex { $0.id == preset.id } ?? 0
                            let selected = model.doc.background.gradientIndex == index
                            Button {
                                model.doc.background.gradientIndex = index
                            } label: {
                                GradientSwatch(colors: preset.colors, angle: preset.angle)
                                    .frame(height: 32)
                                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.85), lineWidth: selected ? 2.5 : 0))
                            }
                            .buttonStyle(.plain)
                            .help(preset.name)
                            .accessibilityLabel(preset.name)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                case .solid:
                    ColorRow(title: L("Color"), color: colorBinding(\.solidColor))
                case .custom:
                    ColorRow(title: L("Start"), color: colorBinding(\.customStart))
                    ColorRow(title: L("End"), color: colorBinding(\.customEnd))
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
                    Text(L("Alignment")).font(.callout).lineLimit(1)
                    Spacer()
                    Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                        ForEach(0..<3, id: \.self) { row in
                            GridRow {
                                ForEach(0..<3, id: \.self) { col in
                                    let alignment = ContentAlignment.allCases[row * 3 + col]
                                    let selected = model.doc.background.alignment == alignment
                                    Button {
                                        model.doc.background.alignment = alignment
                                    } label: {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(selected ? Color.accentColor : Color.secondary.opacity(0.25))
                                            .frame(width: 22, height: 15)
                                    }
                                    .buttonStyle(.plain)
                                    .help(alignment.title)
                                    .accessibilityLabel(alignment.title)
                                    .accessibilityAddTraits(selected ? .isSelected : [])
                                }
                            }
                        }
                    }
                    // A picture of the image's position: left stays left, also in right-to-left languages.
                    .environment(\.layoutDirection, .leftToRight)
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
            FittingSegments(selection: $model.export.format, options: ExportFormat.allCases.map { ($0, $0.title) })
            if model.export.format.supportsQuality {
                LabeledSlider(title: L("Quality"),
                              value: Binding(get: { CGFloat(model.export.quality) }, set: { model.export.quality = Double($0) }),
                              range: 0.1...1) { "\(Int($0 * 100))%" }
            }
        }

        InspectorSection(title: L("Resize")) {
            FittingSegments(selection: $model.export.resizeMode, options: ResizeMode.allCases.map { ($0, $0.title) })

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
                    TextField(L("Width"), value: $model.export.width, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 90)
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
    @Binding var showInspector: Bool
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
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            Spacer(minLength: 8)

            if model.statusMessage == nil {
                let size = model.outputSize
                Text("\(Int(size.width)) × \(Int(size.height)) px · \(model.export.format.title)")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .help(L("Size and format of the exported image"))
            }

            Button { withAnimation(.easeInOut(duration: 0.2)) { showInspector.toggle() } } label: {
                Image(systemName: "sidebar.trailing")
                    .frame(width: 22, height: 18)
            }
            .secondaryButtonStyle()
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help((showInspector ? L("Hide Inspector") : L("Show Inspector")) + "  ⌥⌘I")
            .accessibilityLabel(showInspector ? L("Hide Inspector") : L("Show Inspector"))

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
