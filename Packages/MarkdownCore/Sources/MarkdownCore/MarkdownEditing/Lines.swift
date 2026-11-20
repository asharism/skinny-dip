import Foundation

/// Line commands (#92): ⌥↑/⌥↓ move, ⇧⌥↑/⇧⌥↓ duplicate, ⌘⇧K delete, ⌘L select.
/// They act on the logical lines the selection touches (`lineRanges(touching:)`),
/// not wrapped rows. The empty "line" after a final newline isn't a line: it
/// can't be moved or deleted, so the document's final-newline state never changes.
extension MarkdownEditing {
    /// Swaps the touched lines with the line above (`up`) or below. The
    /// selection moves with them. `nil` at the top or bottom.
    public static func moveLines(_ state: EditorState, up: Bool) -> TextEdit? {
        let text = state.text
        guard let block = touchedBlock(state) else { return nil }
        let blockText = substring(text, block.first.start..<block.last.content.upperBound)
        let blockLength = block.last.content.upperBound - block.first.start
        let selection = state.selection

        if up {
            guard block.first.start > 0 else { return nil }
            let above = lineRange(containing: block.first.start - 1, in: text)
            // A + Ta + B + Tb  →  B + Ta + A + Tb
            let replacement = blockText + above.terminator.rawValue + String(above.text(in: text)) + block.last.terminator.rawValue
            let afterBlock = above.start + blockLength + above.terminator.length
            func map(_ offset: Int) -> Int {
                offset > block.last.content.upperBound ? afterBlock : offset - (block.first.start - above.start)
            }
            return TextEdit(
                range: above.start..<block.last.full.upperBound,
                replacement: replacement,
                selection: map(selection.lowerBound)..<map(selection.upperBound)
            )
        } else {
            guard block.last.terminator != .none else { return nil }
            let below = lineRange(containing: block.last.full.upperBound, in: text)
            if below.terminator == .none, below.content.isEmpty { return nil }
            // B + Tb + C + Tc  →  C + Tb + B + Tc
            let replacement = String(below.text(in: text)) + block.last.terminator.rawValue + blockText + below.terminator.rawValue
            let shift = below.content.count + block.last.terminator.length
            func map(_ offset: Int) -> Int {
                offset > block.last.content.upperBound ? below.full.upperBound : offset + shift
            }
            return TextEdit(
                range: block.first.start..<below.full.upperBound,
                replacement: replacement,
                selection: map(selection.lowerBound)..<map(selection.upperBound)
            )
        }
    }

    /// Copies the touched lines below themselves. The selection ends on the
    /// copy below for Down and stays on the upper lines for Up, as in VS Code.
    public static func duplicateLines(_ state: EditorState, up: Bool) -> TextEdit? {
        let text = state.text
        let lines = lineRanges(touching: state.selection, in: text)
        guard let first = lines.first, let last = lines.last else { return nil }
        let blockText = substring(text, first.start..<last.content.upperBound)
        let insertion: String
        let at: Int
        if last.terminator == .none {
            // The last line: put the break before the copy, never a new trailing one.
            insertion = lineEnding(near: last.start, in: text) + blockText
            at = last.content.upperBound
        } else {
            insertion = blockText + last.terminator.rawValue
            at = last.full.upperBound
        }
        let shift = up ? 0 : insertion.utf16.count
        return TextEdit(
            range: at..<at,
            replacement: insertion,
            selection: (state.selection.lowerBound + shift)..<(state.selection.upperBound + shift)
        )
    }

    /// Removes the touched lines with their line break. The caret lands at the
    /// same column on the next line, or on the previous line at the end of the
    /// document, clamped to a whole character.
    public static func deleteLines(_ state: EditorState) -> TextEdit? {
        let text = state.text
        guard let block = touchedBlock(state) else { return nil }
        let column = state.selection.lowerBound - block.first.start
        if block.last.terminator == .none, block.first.start > 0 {
            // The last line: take the break before it and land on the line above.
            let previous = lineRange(containing: block.first.start - 1, in: text)
            let caret = snap(previous.start + min(column, previous.content.count), in: text)
            return TextEdit(range: previous.content.upperBound..<block.last.content.upperBound, replacement: "", selection: caret..<caret)
        }
        let removed = block.first.start..<block.last.full.upperBound
        let next = lineRange(containing: removed.upperBound, in: text)
        let caretInOld = snap(next.start + min(column, next.content.count), in: text)
        let caret = caretInOld - removed.count
        return TextEdit(range: removed, replacement: "", selection: caret..<caret)
    }

    /// Selects the caret's whole line including its break; with a selection,
    /// extends it to the start of its first line and through the next line.
    /// A pure selection change. `nil` when the selection can't grow.
    public static func selectLine(_ state: EditorState) -> TextEdit? {
        let text = state.text
        let selection = state.selection
        let start = lineRange(containing: selection.lowerBound, in: text).start
        // Through the line the selection ends on; ending at column 0 (after a
        // ⌘L) that's the next line, so pressing it again extends by one line.
        let end = lineRange(containing: selection.upperBound, in: text).full.upperBound
        let selected = start..<end
        guard selected != selection else { return nil }
        return .select(selected)
    }

    /// The touched lines, or `nil` when the only one is the empty "line" after
    /// a final newline (or an empty document): there's nothing to act on.
    private static func touchedBlock(_ state: EditorState) -> (first: LineRange, last: LineRange)? {
        let lines = lineRanges(touching: state.selection, in: state.text)
        guard let first = lines.first, let last = lines.last else { return nil }
        if lines.count == 1, last.terminator == .none, last.content.isEmpty { return nil }
        return (first, last)
    }

    private static func substring(_ text: String, _ range: Range<Int>) -> String {
        (text as NSString).substring(with: NSRange(location: range.lowerBound, length: range.count))
    }

    /// Moves `offset` back to the start of the character it falls inside.
    private static func snap(_ offset: Int, in text: String) -> Int {
        let string = text as NSString
        guard offset < string.length else { return offset }
        return string.rangeOfComposedCharacterSequence(at: offset).location
    }
}
