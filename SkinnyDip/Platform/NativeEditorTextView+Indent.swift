#if os(macOS)
import AppKit
import MarkdownCore

/// Tab / ⇧Tab and Format ▸ Indent ⌘] / Outdent ⌘[ (#91). The rules are in
/// `MarkdownCore/MarkdownEditing/Indent.swift`. Skinny never types a tab
/// character: Tab always indents with spaces.
extension NativeEditorTextView {
    override func insertTab(_ sender: Any?) {
        if !perform(MarkdownEditing.indent) { super.insertTab(sender) }
    }

    override func insertBacktab(_ sender: Any?) {
        if !perform(MarkdownEditing.outdent) { super.insertBacktab(sender) }
    }

    /// Format ▸ Indent (⌘]): indents every line the selection touches, even with a caret.
    @objc func skinnyDipIndent(_ sender: Any?) {
        perform(MarkdownEditing.indentLines)
    }

    /// Format ▸ Outdent (⌘[).
    @objc func skinnyDipOutdent(_ sender: Any?) {
        perform(MarkdownEditing.outdent)
    }
}
#endif
