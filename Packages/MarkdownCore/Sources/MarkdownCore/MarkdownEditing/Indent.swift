import Foundation

/// Tab / ⇧Tab and ⌘] / ⌘[ (#91): indent and outdent with spaces. Skinny never
/// inserts a tab character: tabs nest differently across Markdown renderers and
/// in the Bare HTML paste.
extension MarkdownEditing {
    /// Tab. On a list item, nests it one level (the previous sibling's content
    /// offset). With a caret elsewhere, inserts spaces to the next multiple of 4
    /// columns, also inside fenced code. A selection within one line indents the
    /// line rather than replacing the selection; a multi-line selection indents
    /// every non-blank line it touches. Never `nil`, so AppKit never inserts or
    /// types a tab character over the selection.
    public static func indent(_ state: EditorState) -> TextEdit? {
        let lines = lineRanges(touching: state.selection, in: state.text)
        if lines.count == 1, state.selection.isEmpty, listItem(lines[0], in: state.text) == nil {
            return insertSpacesToTabStop(state, line: lines[0])
        }
        // Only blank lines: handled with no change, so AppKit never types a tab over them.
        return indentLines(state, lines: lines) ?? .select(state.selection)
    }

    /// ⌘]: indents every non-blank line the selection touches, the caret's line
    /// included, by one list level or 4 spaces. `nil` on a blank line.
    public static func indentLines(_ state: EditorState) -> TextEdit? {
        indentLines(state, lines: lineRanges(touching: state.selection, in: state.text))
    }

    /// ⇧Tab and ⌘[: moves a list item to its parent's indent (or column 0), and
    /// removes up to 4 leading spaces, or one leading tab, from other lines.
    /// `nil` when no touched line has any indent.
    public static func outdent(_ state: EditorState) -> TextEdit? {
        let lines = lineRanges(touching: state.selection, in: state.text)
        let changes = lines.compactMap { line -> Change? in
            if lines.count > 1, isBlank(line, in: state.text) { return nil }
            let units = Array(line.text(in: state.text).utf16)
            if let prefix = listItem(line, in: state.text) {
                guard prefix.indent > 0 else { return nil }
                let target = parentIndent(of: line, indent: prefix.indent, in: state.text)
                let indent = units[..<prefix.indentLength]
                if indent.allSatisfy({ $0 == 0x20 }) {
                    return Change(range: line.start..<(line.start + prefix.indent - target), replacement: "")
                }
                return Change(range: line.start..<(line.start + prefix.indentLength), replacement: String(repeating: " ", count: target))
            }
            if units.first == 0x09 { return Change(range: line.start..<(line.start + 1), replacement: "") }
            let spaces = units.prefix(4).prefix { $0 == 0x20 }.count
            guard spaces > 0 else { return nil }
            return Change(range: line.start..<(line.start + spaces), replacement: "")
        }
        return edit(state, lines: lines, changes: changes)
    }

    // MARK: Helpers

    private struct Change {
        var range: Range<Int>
        var replacement: String
    }

    private static func indentLines(_ state: EditorState, lines: [LineRange]) -> TextEdit? {
        let changes = lines.compactMap { line -> Change? in
            if isBlank(line, in: state.text) { return nil }
            let width = listItem(line, in: state.text).map { listIndentWidth(of: line, prefix: $0, in: state.text) } ?? 4
            return Change(range: line.start..<line.start, replacement: String(repeating: " ", count: width))
        }
        return edit(state, lines: lines, changes: changes)
    }

    /// Spaces from the caret to the next multiple of 4 columns. A column is a
    /// character (an emoji is one); a tab advances to the next multiple of 4.
    private static func insertSpacesToTabStop(_ state: EditorState, line: LineRange) -> TextEdit {
        let caret = state.selection.lowerBound
        let before = (state.text as NSString).substring(with: NSRange(location: line.start, length: caret - line.start))
        let column = before.reduce(0) { $1 == "\t" ? ($0 / 4 + 1) * 4 : $0 + 1 }
        let spaces = String(repeating: " ", count: 4 - column % 4)
        let end = caret + spaces.utf16.count
        return TextEdit(range: caret..<caret, replacement: spaces, selection: end..<end)
    }

    /// One edit covering every change, with the selection carried along. A
    /// multi-line selection ends up covering the same lines, now whole.
    private static func edit(_ state: EditorState, lines: [LineRange], changes: [Change]) -> TextEdit? {
        guard let first = changes.first, let last = changes.last else { return nil }
        let text = state.text as NSString
        var replacement = ""
        var cursor = first.range.lowerBound
        for change in changes {
            replacement += text.substring(with: NSRange(location: cursor, length: change.range.lowerBound - cursor))
            replacement += change.replacement
            cursor = change.range.upperBound
        }
        let range = first.range.lowerBound..<last.range.upperBound

        let selection: Range<Int>
        if lines.count > 1, let firstLine = lines.first, let lastLine = lines.last {
            let lower = map(firstLine.start, through: changes, sticky: false)
            let end = state.selection.upperBound >= lastLine.full.upperBound ? state.selection.upperBound : lastLine.content.upperBound
            selection = lower..<map(end, through: changes, sticky: true)
        } else if state.selection.isEmpty {
            let caret = map(state.selection.lowerBound, through: changes, sticky: true)
            selection = caret..<caret
        } else {
            selection = map(state.selection.lowerBound, through: changes, sticky: false)..<map(state.selection.upperBound, through: changes, sticky: true)
        }
        return TextEdit(range: range, replacement: replacement, selection: selection)
    }

    /// Where old offset `x` lands after `changes`. An offset exactly at an
    /// insertion moves after it when `sticky`; one inside a removed span lands
    /// at the end of what replaced it.
    private static func map(_ x: Int, through changes: [Change], sticky: Bool) -> Int {
        var x = x
        for change in changes.reversed() {
            let r = change.range
            let k = change.replacement.utf16.count
            if r.isEmpty {
                if x > r.lowerBound || (x == r.lowerBound && sticky) { x += k }
            } else if x >= r.upperBound {
                x += k - r.count
            } else if x > r.lowerBound {
                x = r.lowerBound + k
            }
        }
        return x
    }

    /// The line's prefix when it's a list item outside a blockquote and outside
    /// fenced code; inside a fence `- a` is code.
    private static func listItem(_ line: LineRange, in text: String) -> LinePrefix? {
        let prefix = linePrefix(line.text(in: text))
        guard prefix.list != nil, prefix.quoteDepth == 0, !isInsideFencedCode(line: line.start, in: text) else { return nil }
        return prefix
    }

    private static func isBlank(_ line: LineRange, in text: String) -> Bool {
        line.text(in: text).allSatisfy { $0 == " " || $0 == "\t" }
    }

    /// One list level: the content offset of the previous item at this indent
    /// (`- ` → 2, `1. ` → 3, `10. ` → 4), else the line's own marker plus a space.
    private static func listIndentWidth(of line: LineRange, prefix: LinePrefix, in text: String) -> Int {
        var start = line.start
        while start > 0 {
            let above = lineRange(containing: start - 1, in: text)
            start = above.start
            let abovePrefix = linePrefix(above.text(in: text))
            guard let marker = abovePrefix.list, abovePrefix.quoteDepth == 0 else {
                // A paragraph at column 0 ends the list; blank and continuation lines don't.
                if abovePrefix.indent == 0, !isBlank(above, in: text) { break }
                continue
            }
            if abovePrefix.indent == prefix.indent { return marker.range.count + 1 }
            if abovePrefix.indent < prefix.indent { break }
        }
        return (prefix.list?.range.count ?? 1) + 1
    }

    /// The indent of the nearest list item above with a smaller indent, else 0.
    private static func parentIndent(of line: LineRange, indent: Int, in text: String) -> Int {
        var start = line.start
        while start > 0 {
            let above = lineRange(containing: start - 1, in: text)
            start = above.start
            let abovePrefix = linePrefix(above.text(in: text))
            if abovePrefix.list != nil, abovePrefix.quoteDepth == 0, abovePrefix.indent < indent { return abovePrefix.indent }
            if abovePrefix.list == nil, abovePrefix.indent == 0, !isBlank(above, in: text) { break }
        }
        return 0
    }
}
