import Foundation

/// Links (#94): paste a URL over a selection to link it, and ⌘K.
extension MarkdownEditing {
    /// The text as one `http(s)` URL, trimmed, or `nil`: no whitespace inside,
    /// `URL(string:)` parses it, and it has a host. `example.com`,
    /// `mailto:` and two URLs on two lines are not one.
    public static func singleURL(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || $0 == "<" || $0 == ">" }),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return trimmed
    }

    /// The URL on the pasteboard, when that's all there is: the plain-text
    /// flavor is one URL, or the HTML's text is just the URL (a link copied
    /// from a page or an address bar), in which case its `<a href>` wins.
    public static func linkURL(in contents: PasteboardContents) -> String? {
        if let url = contents.plainText.flatMap(singleURL(in:)) { return url }
        if let url = contents.skinnyDipMarkdown.flatMap(singleURL(in:)) { return url }
        guard let html = contents.html, let textURL = singleURL(in: htmlText(html)) else { return nil }
        let hrefs = matches(of: #"<a\b[^>]*?\bhref\s*=\s*(?:"([^"]*)"|'([^']*)')"#, in: html).map(decodeEntities)
        if hrefs.count == 1, let href = singleURL(in: hrefs[0]) { return href }
        return textURL
    }

    /// Paste a URL over a selection (⌘V): `[selection](url)`, caret after.
    /// `nil` unless `url` is one URL and the selection is non-empty, on one
    /// line, outside fenced code and not itself a URL; Paste as Markdown runs then.
    public static func pasteLink(_ state: EditorState, url: String) -> TextEdit? {
        guard let url = singleURL(in: url), !state.selection.isEmpty,
              let selected = linkableText(state), singleURL(in: selected) == nil
        else { return nil }
        return wrap(state, text: escapeLinkText(selected), destination: destination(url), caretInParens: false)
    }

    /// ⌘K: link the selection, taking the destination from the clipboard.
    ///
    /// | Selection          | Clipboard URL | Result               |
    /// |--------------------|---------------|----------------------|
    /// | text               | yes           | `[text](url)|`       |
    /// | text               | no            | `[text](|)`          |
    /// | text that's a URL  | either        | `[|](url)`           |
    /// | empty              | yes           | `[|](url)`           |
    /// | empty              | no            | `[|]()`              |
    ///
    /// `nil` across lines and inside fenced code.
    public static func insertLink(_ state: EditorState, clipboardURL: String?) -> TextEdit? {
        guard let selected = linkableText(state) else { return nil }
        let clipboard = clipboardURL.flatMap(singleURL(in:))
        if let url = singleURL(in: selected) {
            return emptyLink(state, destination: destination(url))
        }
        if selected.isEmpty {
            return emptyLink(state, destination: clipboard.map(destination) ?? "")
        }
        return wrap(state, text: escapeLinkText(selected), destination: clipboard.map(destination) ?? "", caretInParens: clipboard == nil)
    }

    // MARK: Helpers

    /// The selected text, when a link may go there: one line, outside fenced code.
    private static func linkableText(_ state: EditorState) -> String? {
        let selected = (state.text as NSString).substring(with: NSRange(location: state.selection.lowerBound, length: state.selection.count))
        guard !selected.utf16.contains(where: isBreak),
              !isInsideFencedCode(line: state.selection.lowerBound, in: state.text)
        else { return nil }
        return selected
    }

    private static func wrap(_ state: EditorState, text: String, destination: String, caretInParens: Bool) -> TextEdit {
        let replacement = "[\(text)](\(destination))"
        let end = state.selection.lowerBound + replacement.utf16.count
        let caret = caretInParens ? end - 1 : end
        return TextEdit(range: state.selection, replacement: replacement, selection: caret..<caret)
    }

    private static func emptyLink(_ state: EditorState, destination: String) -> TextEdit {
        let caret = state.selection.lowerBound + 1
        return TextEdit(range: state.selection, replacement: "[](\(destination))", selection: caret..<caret)
    }

    /// A URL with parentheses goes in `<…>`, which cmark-gfm reads verbatim, so
    /// a `)` doesn't end the link and the URL stays exactly as copied.
    private static func destination(_ url: String) -> String {
        url.contains("(") || url.contains(")") ? "<\(url)>" : url
    }

    /// Link text may hold balanced brackets as typed; when they don't balance,
    /// every unescaped `[` and `]` gets a backslash so the link stays one link.
    private static func escapeLinkText(_ text: String) -> String {
        var depth = 0
        var balanced = true
        var escaped = false
        for character in text {
            if escaped { escaped = false; continue }
            switch character {
            case "\\": escaped = true
            case "[": depth += 1
            case "]":
                depth -= 1
                if depth < 0 { balanced = false }
            default: break
            }
        }
        if balanced, depth == 0 { return text }
        var result = ""
        escaped = false
        for character in text {
            if !escaped, character == "[" || character == "]" { result.append("\\") }
            escaped = !escaped && character == "\\"
            result.append(character)
        }
        return result
    }

    /// The visible text of an HTML fragment: no tags, comments, styles or scripts.
    private static func htmlText(_ html: String) -> String {
        var text = html
        for pattern in [#"(?is)<(style|script|head)\b.*?</\1\s*>"#, #"(?s)<!--.*?-->"#, #"(?s)<[^>]*>"#] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return decodeEntities(text)
    }

    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        for (entity, character) in [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&#x2F;", "/"), ("&#47;", "/"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: character, options: .caseInsensitive)
        }
        return result
    }

    /// The first non-empty capture group of each match.
    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            (1..<match.numberOfRanges).lazy
                .map { match.range(at: $0) }
                .first { $0.location != NSNotFound }
                .map { ns.substring(with: $0) }
        }
    }
}
