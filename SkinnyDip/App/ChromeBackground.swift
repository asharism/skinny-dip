#if os(macOS)
import AppKit
import SwiftUI
import MarkdownCore

/// The Chrome: the desktop blurred through the window, tinted by the Theme's window
/// gradient (ADR-0005, amended). Cards sit on top and are opaque, so none of this
/// reaches the Editor or the Preview.
struct ChromeBackground: View {
    /// How much of the Theme covers the glass; agreed from the mockup in #54.
    static let tint = 0.62

    var theme: ResolvedTheme
    var points: (UnitPoint, UnitPoint)
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if !reduceTransparency {
                BehindWindowBlur()
            }
            LinearGradient(
                colors: theme.windowGradient.map { Color($0).opacity(reduceTransparency ? 1 : Self.tint) },
                startPoint: points.0,
                endPoint: points.1
            )
        }
        .ignoresSafeArea()
    }
}

private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        // Inactive windows dim the way every other macOS window does.
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
#endif
