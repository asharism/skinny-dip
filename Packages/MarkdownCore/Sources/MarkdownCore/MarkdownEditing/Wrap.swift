import Foundation

/// Wrapping a selection in Markdown syntax (#93): typed pairs and ⌘B / ⌘I.
extension MarkdownEditing {
    /// The characters that wrap a selection when typed over it, and their closers.
    /// Not `'` (apostrophes get typed over selections too often) and not `<`
    /// (raw HTML is escaped, ADR-0001).
    public static let wrapPairs: [Character: Character] = [
        "*": "*", "_": "_", "`": "`", "~": "~", "[": "]", "(": ")", "\"": "\"",
    ]

    /// Typing `character` over a non-empty selection on one line wraps it in
    /// the pair, keeping the selection on the inner text, so `*` twice makes
    /// `**bold**`. `nil` for any other character, a caret, or a selection that
    /// spans lines: AppKit replaces the selection as usual.
    public static func wrap(_ state: EditorState, with character: Character) -> TextEdit? {
        guard let close = wrapPairs[character], !state.selection.isEmpty, isOnOneLine(state.selection, in: state.text) else { return nil }
        let inner = substring(state.selection, of: state.text)
        let open = String(character)
        let start = state.selection.lowerBound + open.utf16.count
        return TextEdit(
            range: state.selection,
            replacement: open + inner + String(close),
            selection: start..<(start + state.selection.count)
        )
    }

    /// ⌘B (`"**"`) and ⌘I (`"*"`): toggle the marker around the selection, or
    /// around the word under the caret, or insert an empty pair with the caret
    /// inside. The selection stays on the inner text; a caret stays where it was.
    ///
    /// Emphasis is read from the `*` runs touching the inner text on each side,
    /// inside or just outside the selection: the shorter run is the level, so
    /// `*` is italic, `**` bold and `***` both. Bold is on at 2 or more stars,
    /// italic at an odd count, so ⌘I inside `**bold**` makes `***bold***`
    /// instead of reading the bold markers as italic ones. Declines a selection
    /// that spans lines: emphasis can't cross a paragraph.
    public static func toggleEmphasis(_ state: EditorState, marker: String) -> TextEdit? {
        let text = state.text as NSString
        let selection = state.selection
        guard !marker.isEmpty, isOnOneLine(selection, in: state.text) else { return nil }

        func isStar(_ index: Int) -> Bool { index >= 0 && index < text.length && text.character(at: index) == 0x2A }

        // The inner text: the selection less matching star runs at its ends,
        // or the word under the caret, or the caret itself.
        var inner: Range<Int>
        if selection.isEmpty {
            inner = wordRange(around: selection.lowerBound, in: state.text) ?? selection
        } else {
            var leading = 0
            while selection.lowerBound + leading < selection.upperBound, isStar(selection.lowerBound + leading) { leading += 1 }
            var trailing = 0
            while selection.upperBound - trailing > selection.lowerBound, isStar(selection.upperBound - trailing - 1) { trailing += 1 }
            var strip = min(leading, trailing)
            if 2 * strip >= selection.count { strip = 0 }
            inner = (selection.lowerBound + strip)..<(selection.upperBound - strip)
        }

        var before = 0
        while isStar(inner.lowerBound - before - 1) { before += 1 }
        var after = 0
        while isStar(inner.upperBound + after) { after += 1 }
        let level = min(before, after)
        let length = marker.utf16.count
        let isOn = length >= 2 ? level >= 2 : level % 2 == 1

        let innerText = substring(inner, of: state.text)
        if isOn {
            let range = (inner.lowerBound - length)..<(inner.upperBound + length)
            let newSelection = selection.isEmpty
                ? (selection.lowerBound - length)..<(selection.lowerBound - length)
                : (inner.lowerBound - length)..<(inner.upperBound - length)
            return TextEdit(range: range, replacement: innerText, selection: newSelection)
        }
        let newSelection = selection.isEmpty
            ? (selection.lowerBound + length)..<(selection.lowerBound + length)
            : (inner.lowerBound + length)..<(inner.upperBound + length)
        return TextEdit(range: inner, replacement: marker + innerText + marker, selection: newSelection)
    }

    /// The word the caret touches, on either side: a run of letters and digits
    /// within its line, in UTF-16 offsets. `nil` between two non-word characters.
    static func wordRange(around caret: Int, in text: String) -> Range<Int>? {
        let line = lineRange(containing: caret, in: text)
        var characters: [(offset: Int, isWord: Bool)] = []
        var offset = line.start
        for character in line.text(in: text) {
            characters.append((offset, character.isLetter || character.isNumber))
            offset += character.utf16.count
        }
        characters.append((offset, false))
        guard let index = characters.firstIndex(where: { $0.offset >= caret }) else { return nil }
        var lower = index
        while lower > 0, characters[lower - 1].isWord { lower -= 1 }
        var upper = index
        while upper < characters.count - 1, characters[upper].isWord { upper += 1 }
        guard lower < upper else { return nil }
        return characters[lower].offset..<characters[upper].offset
    }

    private static func isOnOneLine(_ range: Range<Int>, in text: String) -> Bool {
        let units = text.utf16
        let lower = units.index(units.startIndex, offsetBy: range.lowerBound)
        let upper = units.index(lower, offsetBy: range.count)
        return !units[lower..<upper].contains(where: isBreak)
    }

    private static func substring(_ range: Range<Int>, of text: String) -> String {
        (text as NSString).substring(with: NSRange(location: range.lowerBound, length: range.count))
    }
}
