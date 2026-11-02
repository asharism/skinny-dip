#if os(macOS)
import AppKit

/// Intercepts Writing Tools menu actions so the CodeMirror selection is expanded first (MarkEdit `Application.swift`).
final class SkinnyDipApplication: NSApplication {
    override func sendAction(_ action: Selector, to target: Any?, from sender: Any?) -> Bool {
        if action == Self.showWritingToolsAction {
            Task { @MainActor in
                await EditorWritingToolsCoordinator.activeEditorWebView()?.prepareWritingToolsSelection()
                try? await Task.sleep(nanoseconds: 100_000_000)
                super.sendAction(action, to: target, from: sender)
            }
            return true
        }
        return super.sendAction(action, to: target, from: sender)
    }

    private static let showWritingToolsAction = #selector(NSResponder.showWritingTools(_:))
}

enum EditorWritingToolsCoordinator {
    @MainActor
    static func activeEditorWebView() -> EditorWebView? {
        guard let responder = NSApp.keyWindow?.firstResponder else { return nil }
        if let webView = responder as? EditorWebView { return webView }
        return NSApp.keyWindow?.contentView?.firstDescendant(ofType: EditorWebView.self)
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        if let match = self as? T { return match }
        for subview in subviews {
            if let found = subview.firstDescendant(ofType: type) { return found }
        }
        return nil
    }
}
#endif
