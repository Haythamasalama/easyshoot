import SwiftUI

/// Records where named views end up, so layout tests can check that panels
/// keep their size and never overlap. It does nothing unless a probe is
/// put in the environment, which only the tests do.
final class LayoutProbe {
    private(set) var frames: [String: CGRect] = [:]

    func record(_ name: String, _ frame: CGRect) {
        frames[name] = frame
    }
}

extension EnvironmentValues {
    @Entry var layoutProbe: LayoutProbe? = nil
}

private struct LayoutProbeModifier: ViewModifier {
    let name: String
    @Environment(\.layoutProbe) private var probe

    func body(content: Content) -> some View {
        if let probe {
            content.background(
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    Color.clear
                        .onAppear { probe.record(name, frame) }
                        .onChange(of: frame) { _, new in probe.record(name, new) }
                }
            )
        } else {
            content
        }
    }
}

extension View {
    /// Reports this view's frame to the layout probe under `name`, if a test installed one.
    func layoutProbe(_ name: String) -> some View {
        modifier(LayoutProbeModifier(name: name))
    }
}
