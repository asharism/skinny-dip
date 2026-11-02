#if os(macOS)
import AppKit
import SwiftUI

struct WindowChrome: NSViewRepresentable {
    var title: String
    var background: NSColor
    var appearance: NSAppearance?
    var model: WindowTabModel
    var onWindow: (NSWindow) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = ChromeProbe()
        view.onWindow = { [weak coordinator = context.coordinator] window in
            coordinator?.apply(window)
        }
        context.coordinator.parent = self
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        if let window = nsView.window {
            context.coordinator.apply(window)
        }
    }

    final class Coordinator {
        var parent: WindowChrome?
        private var appliedTitle: String?
        private var appliedAppearance: String?
        private var appliedBackground: NSColor?
        @MainActor
        func apply(_ window: NSWindow) {
            guard let parent else { return }
            if appliedTitle != parent.title {
                appliedTitle = parent.title
                window.title = parent.title
            }
            if appliedBackground != parent.background {
                appliedBackground = parent.background
                window.backgroundColor = parent.background
                window.isOpaque = true
            }
            let appearance = parent.appearance?.name.rawValue ?? ""
            if appliedAppearance != appearance {
                appliedAppearance = appearance
                window.appearance = parent.appearance
            }
            DocumentTabs.configure(window)
            parent.model.attach(window)
            parent.onWindow(window)
        }
    }
}

private final class ChromeProbe: NSView {
    var onWindow: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        let callback = onWindow
        Task { @MainActor in callback?(window) }
    }
}
#endif

#if os(macOS)
/// The bare title bar around the Tab strip. SwiftUI swallows the mouse there,
/// so this view gives back the standard behaviour: drag moves the window and a
/// double-click does what System Settings ▸ Desktop & Dock says (zoom by default).
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.performZoom(nil)
                }
                return
            }
            window.performDrag(with: event)
        }
    }
}
#endif
