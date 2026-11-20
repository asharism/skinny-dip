#if os(macOS)
import AppKit
import MarkdownCore

/// Smart ⌘← (#95): the first press goes to the start of the line's content
/// (after the indent, `>` markers, list marker and task box), the next to
/// column 0. The rule is `MarkdownEditing.smartLineStart`; this only maps the
/// keys to it.
///
/// Keys taken over: ⌘← (`moveToLeftEndOfLine:`) and ⌘⇧←
/// (`moveToLeftEndOfLineAndModifySelection:`), plus the `moveToBeginningOfLine:`
/// pair for custom key bindings. ⌃A (`moveToBeginningOfParagraph:`) stays at
/// column 0 and Home still scrolls the document.
///
/// Only the first visual row of a logical line is smart. On a wrapped
/// continuation row these keys keep AppKit's behavior, the start of that row,
/// as VS Code does. A caret move, not an edit: no undo step.
extension NativeEditorTextView {
    override func moveToLeftEndOfLine(_ sender: Any?) {
        if !moveToSmartLineStart(extending: false) { super.moveToLeftEndOfLine(sender) }
    }

    override func moveToLeftEndOfLineAndModifySelection(_ sender: Any?) {
        if !moveToSmartLineStart(extending: true) { super.moveToLeftEndOfLineAndModifySelection(sender) }
    }

    override func moveToBeginningOfLine(_ sender: Any?) {
        if !moveToSmartLineStart(extending: false) { super.moveToBeginningOfLine(sender) }
    }

    override func moveToBeginningOfLineAndModifySelection(_ sender: Any?) {
        if !moveToSmartLineStart(extending: true) { super.moveToBeginningOfLineAndModifySelection(sender) }
    }

    /// Moves the caret, or the selection's start when `extending`, to the
    /// smart line start. The selection's end is the anchor, as AppKit keeps it
    /// for ⌘⇧←. Returns false to leave the key to AppKit: no single selection
    /// (see `editorState`) or the moving end is on a wrapped continuation row.
    private func moveToSmartLineStart(extending: Bool) -> Bool {
        guard let state = editorState else { return false }
        let moving = state.selection.lowerBound
        guard !isOnWrappedContinuationRow(moving) else { return false }
        let target = MarkdownEditing.smartLineStart(caret: moving, in: state.text)
        let range: NSRange
        if extending {
            let anchor = state.selection.upperBound
            range = NSRange(location: min(target, anchor), length: abs(anchor - target))
        } else {
            range = NSRange(location: target, length: 0)
        }
        // Upstream: the selection's start is its moving end, so ⇧→ next shrinks it from the left.
        setSelectedRange(range, affinity: extending ? .upstream : .downstream, stillSelecting: false)
        scrollRangeToVisible(NSRange(location: target, length: 0))
        return true
    }

    /// True when UTF-16 `offset` sits on the second or a later visual row of a
    /// soft-wrapped line, from the TextKit 2 line fragments of its paragraph.
    /// At a wrap boundary, an upstream caret shows at the end of the row above.
    func isOnWrappedContinuationRow(_ offset: Int) -> Bool {
        guard let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let location = contentManager.location(layoutManager.documentRange.location, offsetBy: offset)
        else { return false }
        layoutManager.ensureLayout(for: NSTextRange(location: location))
        guard let fragment = layoutManager.textLayoutFragment(for: location) else { return false }
        let inParagraph = offset - contentManager.offset(from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
        var row = 0
        for (index, line) in fragment.textLineFragments.enumerated() {
            let start = line.characterRange.location
            // The empty row after a final line break is the next logical line, not a wrap.
            guard start <= inParagraph, line.characterRange.length > 0 else { break }
            if index > 0, start == inParagraph, selectionAffinity == .upstream { break }
            row = index
        }
        return row > 0
    }
}
#endif
