/// What Copy as Rich Text puts on the clipboard. Platform code writes `html` as
/// `public.html` and `plainText` as `public.utf8-plain-text`; the only thing it
/// adds is a private flavor that other apps ignore.
public struct CopyPayload: Sendable, Equatable {
    /// Bare HTML in a minimal UTF-8 document wrapper.
    public let html: String
    /// The copied Markdown Source, exactly as typed.
    public let plainText: String

    public init(html: String, plainText: String) {
        self.html = html
        self.plainText = plainText
    }
}

public enum CopyAsRichText {
    /// The payload for a whole document, or for a Selection Copy when `selection`
    /// is non-empty.
    public static func payload(for source: String, selection: Range<String.Index>? = nil, options: RenderOptions = .default) -> CopyPayload {
        CopyPayload(
            html: wrapped(CopyAsHTML.text(for: source, selection: selection, options: options)),
            plainText: CopyAsMarkdown.text(for: source, selection: selection)
        )
    }

    /// The `meta charset` keeps ☐/☑ and other non-ASCII text intact in Word and Outlook.
    private static func wrapped(_ body: String) -> String {
        "<html><head><meta charset=\"utf-8\"></head><body>\n\(body)\n</body></html>"
    }
}

public enum CopyAsMarkdown {
    /// The selected Markdown Source exactly as typed, or the whole document when
    /// `selection` is empty.
    public static func text(for source: String, selection: Range<String.Index>? = nil) -> String {
        guard let selection, !selection.isEmpty else { return source }
        return String(source[selection])
    }
}

public enum CopyAsHTML {
    /// The Bare HTML that Copy as Rich Text would paste, without its document
    /// wrapper, for pasting as HTML source.
    public static func text(for source: String, selection: Range<String.Index>? = nil, options: RenderOptions = .default) -> String {
        guard let selection, !selection.isEmpty else {
            return BareHTML.render(source, options: options)
        }

        // Selection Copy: the selection renders as a document of its own, plus the
        // whole document's link definitions so its reference links still resolve.
        var markdown = String(source[selection])
        if markdown.contains("[") {
            let definitions = linkReferenceDefinitions(in: source)
            if !definitions.isEmpty {
                markdown += "\n\n" + definitions.joined(separator: "\n")
            }
        }
        return BareHTML.render(markdown, options: options)
    }

    /// Lines like `[docs]: https://example.com`. cmark resolves and drops these
    /// while parsing, so they're found in the source text instead.
    private static func linkReferenceDefinitions(in source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.wholeMatch(of: /\ {0,3}\[[^\]]+\]:\s*\S+.*/) != nil }
            .map(String.init)
    }
}
