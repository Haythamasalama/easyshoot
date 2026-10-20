import AppKit
import ScreenCaptureKit
import SwiftUI

/// Repeatedly captures a fixed screen region while the user (or auto-scroll) scrolls the content
/// underneath, and stitches the frames into one tall image. Works with any app.
@MainActor
final class ScrollingCaptureController: ObservableObject {
    @Published var capturedHeight = 0
    @Published var status = L("Scroll down slowly, or press Auto-scroll.")
    @Published var isAutoScrolling = false

    let rect: CGRect
    let screen: NSScreen
    var onFinish: ((CGImage?, CGFloat) -> Void)?

    private let stitcher = ImageStitcher()
    private var borderWindow: NSWindow?
    private var panel: NSPanel?
    private var loopTask: Task<Void, Never>?
    private var filter: SCContentFilter?
    private var configuration: SCStreamConfiguration?
    private var unchangedCount = 0
    private var finished = false

    /// `rect` is in global Cocoa coordinates (bottom-left origin).
    init(rect: CGRect, screen: NSScreen) {
        self.rect = rect
        self.screen = screen
    }

    func start() {
        showBorder()
        showPanel()
        loopTask = Task { [weak self] in
            await self?.prepare()
            while let self, !self.finished, !Task.isCancelled {
                await self.tick()
            }
        }
    }

    func finish() {
        guard !finished else { return }
        finished = true
        loopTask?.cancel()
        closeWindows()
        let image = stitcher.makeImage()
        onFinish?(image, screen.backingScaleFactor)
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        loopTask?.cancel()
        closeWindows()
        onFinish?(nil, screen.backingScaleFactor)
    }

    func toggleAutoScroll() {
        if !isAutoScrolling {
            guard Permissions.hasAccessibility else {
                Permissions.requestAccessibility()
                status = L("Auto-scroll needs Accessibility access: enable EasyShoot in System Settings → Privacy & Security → Accessibility.")
                return
            }
            CGWarpMouseCursorPosition(regionCenterInCGCoordinates)
        }
        isAutoScrolling.toggle()
        unchangedCount = 0
    }

    // MARK: Capture loop

    private func prepare() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                status = L("Could not find the display.")
                return
            }
            // Exclude EasyShoot's own windows (border + control panel) from the frames.
            let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

            let config = SCStreamConfiguration()
            // sourceRect uses the display's point coordinates with a top-left origin.
            config.sourceRect = CGRect(x: rect.minX - screen.frame.minX,
                                       y: screen.frame.maxY - rect.maxY,
                                       width: rect.width, height: rect.height)
            let scale = screen.backingScaleFactor
            config.width = Int(rect.width * scale)
            config.height = Int(rect.height * scale)
            config.showsCursor = false
            config.captureResolution = .best
            configuration = config
        } catch {
            status = L("Screen Recording permission is required for scrolling capture.")
        }
    }

    private func tick() async {
        guard let filter, let configuration else {
            try? await Task.sleep(nanoseconds: 300_000_000)
            return
        }
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            let stitcher = self.stitcher
            let result = await Task.detached(priority: .userInitiated) { stitcher.add(image) }.value
            guard !finished else { return }
            handle(result)
        } catch {
            status = error.localizedDescription
        }
        guard !finished else { return }
        if isAutoScrolling {
            scrollStep()
            try? await Task.sleep(nanoseconds: 450_000_000)
        } else {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func handle(_ result: ImageStitcher.AddResult) {
        switch result {
        case .first, .appended:
            capturedHeight = stitcher.height
            unchangedCount = 0
            status = isAutoScrolling ? L("Auto-scrolling… press Done any time.") : L("Capturing… keep scrolling, then press Done.")
        case .unchanged:
            unchangedCount += 1
            if isAutoScrolling && unchangedCount >= 4 {
                status = L("Reached the end.")
                finish()
            }
        case .noOverlap:
            status = L("Scrolled too fast — scroll back up a little and continue slower.")
        case .limitReached:
            status = L("Maximum height reached.")
            finish()
        }
    }

    private var regionCenterInCGCoordinates: CGPoint {
        // CoreGraphics global coordinates have a top-left origin on the primary display.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        return CGPoint(x: rect.midX, y: primaryHeight - rect.midY)
    }

    private func scrollStep() {
        let amount = Int32(max(40, rect.height * 0.45))
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                  wheel1: -amount, wheel2: 0, wheel3: 0) else { return }
        event.location = regionCenterInCGCoordinates
        event.post(tap: .cghidEventTap)
    }

    // MARK: Windows

    private func showBorder() {
        let frame = rect.insetBy(dx: -4, dy: -4)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true // scrolling passes straight through to the app below
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = RegionBorderView(frame: CGRect(origin: .zero, size: frame.size))
        window.orderFrontRegardless()
        borderWindow = window
    }

    private func showPanel() {
        // The panel is as tall as its text needs; translations can run to three lines.
        let content = FirstMouseHostingView(rootView: ScrollingPanelView(controller: self))
        let size = CGSize(width: 360, height: max(130, content.fittingSize.height))
        let visible = screen.visibleFrame
        var origin = CGPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 14)
        if origin.y < visible.minY {
            origin.y = rect.maxY + 14
            if origin.y + size.height > visible.maxY { origin.y = rect.minY + 14 }
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)

        let panel = FloatingPanel(contentRect: CGRect(origin: origin, size: size),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = content
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func closeWindows() {
        borderWindow?.orderOut(nil)
        panel?.orderOut(nil)
        borderWindow = nil
        panel = nil
    }
}

private final class RegionBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 4, yRadius: 4)
        path.lineWidth = 2
        path.setLineDash([8, 5], count: 2, phase: 0)
        Brand.signalNS.setStroke()
        path.stroke()
    }
}

struct ScrollingPanelView: View {
    @ObservedObject var controller: ScrollingCaptureController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "scroll")
                Text(L("Scrolling Capture")).font(.headline)
                Spacer()
                Text("\(controller.capturedHeight) px")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(controller.status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button {
                    controller.toggleAutoScroll()
                } label: {
                    Label(controller.isAutoScrolling ? L("Pause") : L("Auto-scroll"),
                          systemImage: controller.isAutoScrolling ? "pause.fill" : "arrow.down.circle")
                }
                Spacer()
                Button(L("Cancel")) { controller.cancel() }
                    .secondaryButtonStyle()
                Button(L("Done")) { controller.finish() }
                    .primaryButtonStyle()
            }
        }
        .padding(14)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .glassSurface(cornerRadius: 16)
    }
}
