extension MarkdownEditing {
    /// Smart ⌘← (#95), VS Code's smart Home on the Mac key: where the caret at
    /// UTF-16 `caret` goes. First to the start of the line's content (after the
    /// indent, `>` markers, list marker and task box), then, from there, to
    /// column 0. A line with no prefix goes straight to column 0. A caret move,
    /// not an edit, so it returns an offset rather than a `TextEdit`.
    public static func smartLineStart(caret: Int, in text: String) -> Int {
        let line = lineRange(containing: caret, in: text)
        let contentStart = line.start + linePrefix(line.text(in: text)).contentStart
        return caret == contentStart ? line.start : contentStart
    }
}
