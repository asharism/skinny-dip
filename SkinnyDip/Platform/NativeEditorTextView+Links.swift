#if os(macOS)
import AppKit
import MarkdownCore

/// Links (#94): ⌘K links the selection, taking the URL from the clipboard
/// (`MarkdownEditing.insertLink`). Pasting a URL over a selection is in
/// `insertMarkdownFromPasteboard(plain:)`.
extension NativeEditorTextView {
    /// The Format menu's Link (⌘K). Reads the clipboard through `pasteboard`,
    /// so tests can point it at a private one.
    @objc func skinnyDipInsertLink(_ sender: Any?) {
        let url = MarkdownEditing.linkURL(in: pasteboard.pasteContents)
        perform { MarkdownEditing.insertLink($0, clipboardURL: url) }
    }
}
#endif
