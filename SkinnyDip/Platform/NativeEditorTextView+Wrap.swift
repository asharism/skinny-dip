#if os(macOS)
import AppKit
import MarkdownCore

/// Wrap (#93): a pair character typed over a selection wraps it, and ⌘B / ⌘I
/// toggle bold and italic. The rules are `MarkdownEditing.wrap` and
/// `MarkdownEditing.toggleEmphasis`.
///
/// Keys taken over from AppKit: typing `*` `_` `` ` `` `~` `[` `(` `"` over a
/// one-line selection no longer replaces it. ⌘B and ⌘I are free in Skinny:
/// there is no Font menu, so nothing else answers them.
extension NativeEditorTextView {
    /// Only a key press wraps. Paste and other programmatic inserts call
    /// `insertText` too, but never inside `keyDown`, so they replace as usual.
    override func keyDown(with event: NSEvent) {
        let outer = isTypingFromKeyboard
        isTypingFromKeyboard = true
        defer { isTypingFromKeyboard = outer }
        super.keyDown(with: event)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if isTypingFromKeyboard,
           replacementRange.location == NSNotFound || replacementRange == selectedRange(),
           let typed = (string as? String) ?? (string as? NSAttributedString)?.string,
           typed.count == 1, let character = typed.first,
           MarkdownEditing.wrapPairs[character] != nil,
           perform({ MarkdownEditing.wrap($0, with: character) }) {
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    @objc func skinnyDipToggleBold(_ sender: Any?) {
        perform { MarkdownEditing.toggleEmphasis($0, marker: "**") }
    }

    @objc func skinnyDipToggleItalic(_ sender: Any?) {
        perform { MarkdownEditing.toggleEmphasis($0, marker: "*") }
    }
}

/// The Format menu's Wrap selectors.
enum WrapCommands {
    static let boldSelector = #selector(NativeEditorTextView.skinnyDipToggleBold(_:))
    static let italicSelector = #selector(NativeEditorTextView.skinnyDipToggleItalic(_:))
}

/// Set while a key press is being interpreted (one editor has focus at a time).
@MainActor private var isTypingFromKeyboard = false
#endif
