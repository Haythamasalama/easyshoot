import AppKit
import Combine
import SwiftUI

@MainActor
final class EditorModel: ObservableObject {
    @Published var doc: EditorDocument
    @Published var tool: Tool = .arrow {
        didSet { toolChanged(from: oldValue) }
    }
    /// Style used for new annotations.
    @Published var style: AnnotationStyle
    @Published var selectedID: UUID?
    /// Crop rect being edited while the crop tool is active (image pixels).
    @Published var cropDraft: CGRect
    @Published var export: ExportOptions
    @Published var statusMessage: String?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    weak var window: NSWindow?
    /// Set by the canvas so pending text edits are committed before exporting.
    var commitPendingEdits: (() -> Void)?

    private struct Snapshot {
        var annotations: [Annotation]
        var crop: CGRect
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var lastStyleUndoID: UUID?
    private var toolBeforeCrop: Tool = .arrow
    private var pixelatedCache: CGImage?
    private var pixelatedComputed = false
    private var statusClearTask: Task<Void, Never>?
    private var lastUsedSink: AnyCancellable?

    /// Starts from the default preset when one is set, otherwise from the last screenshot's settings.
    init(result: CaptureResult, preset: Preset?, lastUsed: LastUsed? = nil) {
        var doc = EditorDocument(image: result.image, scale: result.scale)
        if let preset {
            doc.background = preset.background
            self.style = preset.style
            self.export = preset.export
        } else if let lastUsed {
            doc.background = lastUsed.background
            self.style = lastUsed.style
            self.export = lastUsed.export
            if let tool = Tool(rawValue: lastUsed.tool), tool != .crop { self.tool = tool }
        } else {
            self.style = AnnotationStyle()
            self.export = ExportOptions()
        }
        self.doc = doc
        self.cropDraft = doc.crop
    }

    /// Saves background, style, export options and tool as they change, for the next screenshot.
    func rememberSettings(in defaults: UserDefaults = .standard) {
        lastUsedSink = Publishers.CombineLatest4($doc.map(\.background), $style, $export, $tool)
            .map { LastUsed(background: $0, style: $1, export: $2, tool: ($3 == .crop ? Tool.select : $3).rawValue) }
            .removeDuplicates()
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { LastUsedStore.save($0, to: defaults) }
    }

    // MARK: Derived

    var isCropping: Bool { tool == .crop }

    var selectedAnnotation: Annotation? {
        guard let id = selectedID else { return nil }
        return annotation(id)
    }

    func annotation(_ id: UUID) -> Annotation? {
        doc.annotations.first { $0.id == id }
    }

    var nextCounterNumber: Int {
        (doc.annotations.filter { $0.kind == .counter }.map(\.number).max() ?? 0) + 1
    }

    var pixelated: CGImage? {
        if !pixelatedComputed {
            pixelatedCache = Renderer.pixelate(doc.image, scale: doc.scale)
            pixelatedComputed = true
        }
        return pixelatedCache
    }

    var needsPixelated: Bool { doc.annotations.contains { $0.kind == .pixelate } }

    // MARK: Style

    /// The floating text bar shows for the text tool and whenever a text is selected.
    var showsTextBar: Bool {
        tool == .text || selectedAnnotation?.kind == .text || selectedAnnotation?.kind == .counter
    }

    func adjustFontSize(by delta: CGFloat) {
        var newStyle = activeStyle
        newStyle.fontSize = min(200, max(8, (newStyle.fontSize + delta).rounded()))
        setActiveStyle(newStyle)
    }

    /// Style shown in the inspector: the selected annotation's, or the one used for new annotations.
    var activeStyle: AnnotationStyle { selectedAnnotation?.style ?? style }

    func setActiveStyle(_ newStyle: AnnotationStyle) {
        style = newStyle
        guard let id = selectedID, let current = annotation(id), current.style != newStyle else { return }
        if lastStyleUndoID != id {
            registerUndo()
            lastStyleUndoID = id
        }
        update(id) { $0.style = newStyle }
    }

    // MARK: Editing

    func registerUndo() {
        undoStack.append(Snapshot(annotations: doc.annotations, crop: doc.crop))
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
        lastStyleUndoID = nil
        refreshUndoFlags()
    }

    func undo() {
        commitPendingEdits?()
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(Snapshot(annotations: doc.annotations, crop: doc.crop))
        restore(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(Snapshot(annotations: doc.annotations, crop: doc.crop))
        restore(snapshot)
    }

    private func restore(_ snapshot: Snapshot) {
        doc.annotations = snapshot.annotations
        doc.crop = snapshot.crop
        cropDraft = snapshot.crop
        if let id = selectedID, annotation(id) == nil { selectedID = nil }
        lastStyleUndoID = nil
        refreshUndoFlags()
    }

    private func refreshUndoFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func add(_ a: Annotation) {
        registerUndo()
        doc.annotations.append(a)
        selectedID = a.id
    }

    func update(_ id: UUID, _ body: (inout Annotation) -> Void) {
        guard let i = doc.annotations.firstIndex(where: { $0.id == id }) else { return }
        body(&doc.annotations[i])
    }

    /// Removes without registering undo (used to discard empty text boxes).
    func discard(_ id: UUID) {
        doc.annotations.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        registerUndo()
        doc.annotations.removeAll { $0.id == id }
        selectedID = nil
    }

    func clearAnnotations() {
        guard !doc.annotations.isEmpty else { return }
        registerUndo()
        doc.annotations.removeAll()
        selectedID = nil
    }

    func bringSelectedToFront() {
        guard let id = selectedID, let i = doc.annotations.firstIndex(where: { $0.id == id }) else { return }
        registerUndo()
        let a = doc.annotations.remove(at: i)
        doc.annotations.append(a)
    }

    // MARK: Crop

    private func toolChanged(from old: Tool) {
        if tool == .crop {
            if old != .crop { toolBeforeCrop = old }
            cropDraft = doc.crop
            selectedID = nil
        }
    }

    func applyCrop() {
        let r = cropDraft.standardized.integral.intersection(doc.fullRect)
        guard !r.isNull, r.width >= 4, r.height >= 4 else { return }
        if r != doc.crop {
            registerUndo()
            doc.crop = r
        }
        tool = toolBeforeCrop == .crop ? .select : toolBeforeCrop
    }

    func cancelCrop() {
        cropDraft = doc.crop
        tool = toolBeforeCrop == .crop ? .select : toolBeforeCrop
    }

    func resetCropDraft() {
        cropDraft = doc.fullRect
    }

    /// Largest centered crop with the given aspect ratio.
    func setCropAspect(_ ratio: CGFloat?) {
        guard let ratio else { return }
        let full = doc.fullRect
        var w = full.width, h = full.width / ratio
        if h > full.height { h = full.height; w = h * ratio }
        cropDraft = CGRect(x: (full.width - w) / 2, y: (full.height - h) / 2, width: w, height: h).integral
    }

    // MARK: Presets

    func apply(_ preset: Preset) {
        doc.background = preset.background
        style = preset.style
        export = preset.export
        flash(L("Applied “%@”", preset.name))
    }

    func makePreset(named name: String) -> Preset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Preset(name: trimmed.isEmpty ? L("My Preset") : trimmed, background: doc.background, style: style, export: export)
    }

    // MARK: Export

    var outputSize: CGSize {
        let layout = Renderer.layout(for: doc)
        let f = export.factor(canvasWidth: layout.canvasSize.width)
        return CGSize(width: (layout.canvasSize.width * f).rounded(), height: (layout.canvasSize.height * f).rounded())
    }

    private func renderForExport() -> (image: CGImage, dpiScale: CGFloat)? {
        commitPendingEdits?()
        let layout = Renderer.layout(for: doc)
        let f = export.factor(canvasWidth: layout.canvasSize.width)
        guard let image = Renderer.renderImage(doc, factor: f, pixelated: needsPixelated ? pixelated : nil,
                                               opaque: export.format == .jpeg) else { return nil }
        return (image, doc.scale * f)
    }

    func copyToClipboard() {
        guard let r = renderForExport() else { return }
        ExportService.copyToPasteboard(r.image, dpiScale: r.dpiScale)
        flash(L("Copied to clipboard"))
    }

    func saveQuick() {
        guard let r = renderForExport() else { return }
        do {
            let url = try ExportService.save(r.image, options: export, dpiScale: r.dpiScale, to: ExportService.defaultSaveURL(for: export.format))
            flash(L("Saved %@", url.lastPathComponent))
        } catch {
            flash(L("Save failed: %@", error.localizedDescription))
        }
    }

    func saveAs() {
        guard let r = renderForExport() else { return }
        let options = export
        ExportService.saveWithPanel(r.image, options: options, dpiScale: r.dpiScale, window: window) { [weak self] url in
            if let url { self?.flash(L("Saved %@", url.lastPathComponent)) }
        }
    }

    func flash(_ message: String) {
        statusMessage = message
        statusClearTask?.cancel()
        statusClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled { self?.statusMessage = nil }
        }
    }
}
