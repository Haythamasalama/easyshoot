import AppKit
import SwiftUI

/// Floating thumbnails shown after each capture (bottom-left of the screen):
/// copy, save, annotate, drag into any app, or dismiss.
@MainActor
final class QuickAccessManager {
    static let shared = QuickAccessManager()

    private var panels: [QuickAccessPanel] = []
    private var hidden = false

    func show(_ result: CaptureResult) {
        let panel = QuickAccessPanel(result: result, manager: self)
        panels.append(panel)
        if panels.count > 5, let oldest = panels.first { close(oldest) }
        relayout()
        if !hidden { panel.orderFrontRegardless() }

        let delay = AppSettings.shared.quickAccessAutoClose
        if delay > 0 {
            Task { @MainActor [weak self, weak panel] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, let panel, !panel.isHovered else { return }
                self.close(panel)
            }
        }
    }

    func close(_ panel: QuickAccessPanel) {
        panel.orderOut(nil)
        panels.removeAll { $0 === panel }
        relayout()
    }

    /// Hide while taking a new screenshot so thumbnails don't end up in it.
    func setHidden(_ hide: Bool) {
        hidden = hide
        for panel in panels {
            if hide { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
        }
    }

    private func relayout() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        var y = visible.minY + 16
        for panel in panels.reversed() {
            panel.setFrameOrigin(CGPoint(x: visible.minX + 16, y: y))
            y += panel.frame.height + 10
        }
    }

    // MARK: Actions

    func copy(_ panel: QuickAccessPanel) {
        guard let rendered = ExportService.renderWithDefaults(panel.result) else { return }
        ExportService.copyToPasteboard(rendered.image, dpiScale: rendered.dpiScale)
        close(panel)
    }

    func save(_ panel: QuickAccessPanel) {
        guard let rendered = ExportService.renderWithDefaults(panel.result) else { return }
        do {
            let url = try ExportService.save(rendered.image, options: rendered.options, dpiScale: rendered.dpiScale,
                                             to: ExportService.defaultSaveURL(for: rendered.options.format))
            NSWorkspace.shared.activateFileViewerSelecting([url])
            close(panel)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func annotate(_ panel: QuickAccessPanel) {
        CaptureCoordinator.shared.openEditor(panel.result)
        close(panel)
    }

    func dragProvider(_ panel: QuickAccessPanel) -> NSItemProvider {
        guard let rendered = ExportService.renderWithDefaults(panel.result),
              let url = try? ExportService.writeTemporary(rendered.image, options: rendered.options, dpiScale: rendered.dpiScale),
              let provider = NSItemProvider(contentsOf: url) else { return NSItemProvider() }
        return provider
    }
}

final class QuickAccessPanel: FloatingPanel {
    private(set) var result: CaptureResult!
    fileprivate(set) var isHovered = false

    convenience init(result: CaptureResult, manager: QuickAccessManager) {
        let maxSide: CGFloat = 220
        let aspect = CGFloat(result.image.width) / max(1, CGFloat(result.image.height))
        let width = aspect >= 1 ? maxSide : max(110, maxSide * aspect)
        let height = min(max(width / aspect, 90), 240)
        self.init(contentRect: CGRect(x: 0, y: 0, width: width, height: height),
                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.result = result
        isReleasedWhenClosed = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let thumbnail = NSImage(cgImage: result.image, size: CGSize(width: result.image.width, height: result.image.height))
        let view = QuickAccessView(
            image: thumbnail,
            onHover: { [weak self] in self?.isHovered = $0 },
            onCopy: { [weak self, weak manager] in if let self { manager?.copy(self) } },
            onSave: { [weak self, weak manager] in if let self { manager?.save(self) } },
            onEdit: { [weak self, weak manager] in if let self { manager?.annotate(self) } },
            onClose: { [weak self, weak manager] in if let self { manager?.close(self) } },
            dragProvider: { [weak self, weak manager] in
                guard let self, let manager else { return NSItemProvider() }
                return manager.dragProvider(self)
            }
        )
        contentView = FirstMouseHostingView(rootView: view)
    }
}

struct QuickAccessView: View {
    let image: NSImage
    let onHover: (Bool) -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onEdit: () -> Void
    let onClose: () -> Void
    let dragProvider: () -> NSItemProvider

    @State private var hovering = false

    var body: some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            Color.black.opacity(hovering ? 0.45 : 0)

            if hovering {
                VStack(spacing: 8) {
                    pill(L("Copy"), action: onCopy)
                    pill(L("Save"), action: onSave)
                }
                VStack {
                    HStack {
                        circleButton("xmark", help: L("Close"), action: onClose)
                        Spacer()
                        circleButton("pencil", help: L("Annotate"), action: onEdit)
                    }
                    Spacer()
                }
                .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.35), lineWidth: 1))
        .background(HoverTracker { inside in
            hovering = inside
            onHover(inside)
        })
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
        .onDrag(dragProvider)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 84, height: 26)
                .background(Capsule().fill(Color.white))
        }
        .buttonStyle(.plain)
    }

    private func circleButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
