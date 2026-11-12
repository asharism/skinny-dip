#if os(macOS)
import AppKit

/// What the menus, ⌘V and Writing Tools need from whichever Editor Backend is
/// running (ADR-0010). The responder class itself conforms, so the shell never
/// names `EditorWebView` or the native text view.
@MainActor
protocol EditorResponder: NSResponder {
    /// ⌘V (Paste as Markdown) or, with `plain`, ⌥⇧⌘V: one undoable insert.
    func insertMarkdownFromPasteboard(plain: Bool)
    func skinnyDipUndo(_ sender: Any?)
    func skinnyDipRedo(_ sender: Any?)
    /// Called before Writing Tools opens, so it sees the selection it should.
    func prepareWritingToolsSelection() async
}

@MainActor
enum EditorResponders {
    /// The Edit menu sends these down the responder chain; every backend answers them.
    static let undoSelector = NSSelectorFromString("skinnyDipUndo:")
    static let redoSelector = NSSelectorFromString("skinnyDipRedo:")

    /// The editor in the key window: the first responder or one of its ancestors,
    /// else the editor anywhere in the window. A different text field holding focus
    /// (Settings, an open panel, a rename field) means no editor.
    static func active() -> (any EditorResponder)? {
        let window = NSApp.keyWindow
        if let editor = enclosing(window?.firstResponder) { return editor }
        if window?.firstResponder is NSTextView { return nil }
        return descendant(in: window?.contentView)
    }

    static func enclosing(_ responder: NSResponder?) -> (any EditorResponder)? {
        var current = responder
        while let next = current {
            if let editor = next as? any EditorResponder { return editor }
            current = next.nextResponder
        }
        return nil
    }

    static func descendant(in view: NSView?) -> (any EditorResponder)? {
        guard let view else { return nil }
        if let editor = view as? any EditorResponder { return editor }
        for child in view.subviews {
            if let editor = descendant(in: child) { return editor }
        }
        return nil
    }
}
#endif
