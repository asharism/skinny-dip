extension MarkdownEditing {
    /// Enter (#90): continues the list item or blockquote the caret is in, the
    /// way VS Code with Markdown All in One does.
    ///
    /// - `- a|` → `- a\n- |`, keeping the indent, quote markers, bullet and
    ///   spacing; `1. a|` → `1. a\n2. |` (following items aren't renumbered,
    ///   ADR-0012); a task item continues as `[ ]`. Text after the caret moves
    ///   to the new item.
    /// - An empty item or quote (`- |`, `> |`) loses its prefix: the list ends
    ///   and the line is left empty.
    /// - An indented plain line keeps its indent.
    ///
    /// A selection on one line is replaced first. Declines (`nil`) for a
    /// multi-line selection, a caret before the line's content, a plain or
    /// whitespace-only line, a thematic break, and inside a fenced code block.
    public static func newline(_ state: EditorState) -> TextEdit? {
        let text = state.text
        let selection = state.selection
        let line = lineRange(containing: selection.lowerBound, in: text)
        guard selection.upperBound <= line.content.upperBound else { return nil }
        guard !isInsideFencedCode(line: line.start, in: text) else { return nil }

        let lineText = line.text(in: text)
        let units = Array(lineText.utf16)
        let prefix = linePrefix(lineText)
        let caret = selection.lowerBound - line.start
        guard caret >= prefix.contentStart else { return nil }
        // What's left of the item's text once the selection is replaced.
        let remaining = units[prefix.contentStart..<caret].count + units[(selection.upperBound - line.start)...].count

        guard prefix.hasMarker else {
            // An indented plain line keeps its indent; anything else is AppKit's.
            guard prefix.indentLength > 0, remaining > 0 else { return nil }
            let indent = String(decoding: units[..<prefix.indentLength], as: UTF16.self)
            return insertBreak(lineEnding(near: selection.lowerBound, in: text) + indent, over: selection)
        }
        guard !isThematicBreak(units) else { return nil }

        if remaining == 0 {
            // An empty item: remove the marker and end the list.
            return TextEdit(range: line.content, replacement: "", selection: line.start..<line.start)
        }

        var continuation: String
        if let list = prefix.list {
            continuation = String(decoding: units[..<list.range.lowerBound], as: UTF16.self)
            switch list.kind {
            case .bullet(let bullet): continuation.append(bullet)
            case .ordered(let number, let delimiter): continuation += "\(number + 1)\(delimiter)"
            }
            if let task = prefix.task {
                continuation += String(decoding: units[list.range.upperBound..<task.range.lowerBound], as: UTF16.self)
                continuation += "[ ]"
                continuation += String(decoding: units[task.range.upperBound..<prefix.contentStart], as: UTF16.self)
            } else {
                continuation += String(decoding: units[list.range.upperBound..<prefix.contentStart], as: UTF16.self)
            }
        } else {
            continuation = String(decoding: units[..<prefix.contentStart], as: UTF16.self)
        }
        return insertBreak(lineEnding(near: selection.lowerBound, in: text) + continuation, over: selection)
    }

    private static func insertBreak(_ replacement: String, over selection: Range<Int>) -> TextEdit {
        let caret = selection.lowerBound + replacement.utf16.count
        return TextEdit(range: selection, replacement: replacement, selection: caret..<caret)
    }

    /// `- - -`, `* * *`, `___`: three or more of one of `-*_`, spaces between.
    private static func isThematicBreak(_ units: [UInt16]) -> Bool {
        let marks = units.filter { $0 != 0x20 && $0 != 0x09 }
        guard marks.count >= 3, let first = marks.first, first == 0x2D || first == 0x2A || first == 0x5F else { return false }
        return marks.allSatisfy { $0 == first }
    }
}
