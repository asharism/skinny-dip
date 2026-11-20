#if os(macOS)
import AppKit
import MarkdownCore

/// Editing Commands (ADR-0012): the Markdown rules are pure functions in
/// `MarkdownCore/MarkdownEditing`; this is only the bridge that runs one on the
/// text view's state and applies its edit as one undo step.
///
/// Each feature hooks in from its own `NativeEditorTextView+<Feature>.swift`
/// extension, overriding the `NSTextView` action it takes over and falling
/// through to `super` when `perform` returns false:
///
///     override func insertNewline(_ sender: Any?) {
///         if !perform(MarkdownEditing.newline) { super.insertNewline(sender) }
///     }
extension NativeEditorTextView {
    /// The text and the one selection, in UTF-16 offsets. `nil` whenever an
    /// Editing Command should leave the key to AppKit: several selections
    /// (⌥-drag), marked text (IME, dictation), or an active Writing Tools session.
    var editorState: EditorState? {
        let ranges = selectedRanges.map(\.rangeValue)
        guard ranges.count == 1, let range = ranges.first, !hasMarkedText(), !isWritingToolsActive else { return nil }
        return EditorState(text: string, selection: range.location..<NSMaxRange(range))
    }

    /// Runs `command` on the current state and applies its edit. Returns false
    /// when there's no state or the command declines (`nil`), so the caller can
    /// fall through to `super`.
    @discardableResult
    func perform(_ command: (EditorState) -> TextEdit?) -> Bool {
        guard let state = editorState, let edit = command(state) else { return false }
        apply(edit)
        return true
    }

    /// Applies `edit` as one undo step whose undo restores the old text and the
    /// selection the command saw, and whose redo restores the edit and its
    /// selection. AppKit's own text undo doesn't reliably restore the selection
    /// (it often leaves a caret at the edit), so this edit skips it and
    /// registers its inverse `TextEdit` instead; applying that registers the
    /// redo the same way. A selection-only edit just moves the selection, with
    /// no undo step.
    func apply(_ edit: TextEdit) {
        let selection = NSRange(location: edit.selection.lowerBound, length: edit.selection.count)
        guard !edit.isSelectionOnly else {
            setSelectedRange(selection)
            return
        }
        let range = NSRange(location: edit.range.lowerBound, length: edit.range.count)
        let before = selectedRange()
        let removed = (string as NSString).substring(with: range)
        breakUndoCoalescing()
        let allowedUndo = allowsUndo
        allowsUndo = false
        let changed = shouldChangeText(in: range, replacementString: edit.replacement)
        if changed {
            textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: edit.replacement, attributes: editingAttributes))
            didChangeText()
        }
        allowsUndo = allowedUndo
        setSelectedRange(selection)
        breakUndoCoalescing()
        guard changed, allowedUndo else { return }
        let inverse = TextEdit(
            range: edit.range.lowerBound..<(edit.range.lowerBound + edit.replacement.utf16.count),
            replacement: removed,
            selection: before.location..<NSMaxRange(before)
        )
        undoManager?.registerUndo(withTarget: self) { $0.apply(inverse) }
    }

    /// The theme's base attributes, as `replaceAll` uses: never whatever run the
    /// caret was sitting on. The highlighter restyles the text after the edit.
    private var editingAttributes: [NSAttributedString.Key: Any] {
        editorCoordinator?.baseAttributes ?? typingAttributes
    }
}
#endif
