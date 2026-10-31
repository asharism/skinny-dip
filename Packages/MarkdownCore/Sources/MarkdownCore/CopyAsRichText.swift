/// What Copy as Rich Text puts on the clipboard. Platform code writes `html` as
/// `public.html` and `plainText` as `public.utf8-plain-text`; it adds nothing.
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
        guard let selection, !selection.isEmpty else {
            return CopyPayload(html: wrapped(BareHTML.render(source, options: options)), plainText: source)
        }

        // Selection Copy: the selection renders as a document of its own, plus the
        // whole document's link definitions so its reference links still resolve.
        let selected = String(source[selection])
        var markdown = selected
        if selected.contains("[") {
            let definitions = linkReferenceDefinitions(in: source)
            if !definitions.isEmpty {
                markdown += "\n\n" + definitions.joined(separator: "\n")
            }
        }
        return CopyPayload(html: wrapped(BareHTML.render(markdown, options: options)), plainText: selected)
    }

    /// The `meta charset` keeps ☐/☑ and other non-ASCII text intact in Word and Outlook.
    private static func wrapped(_ body: String) -> String {
        "<html><head><meta charset=\"utf-8\"></head><body>\n\(body)\n</body></html>"
    }

    /// Lines like `[docs]: https://example.com`. cmark resolves and drops these
    /// while parsing, so they're found in the source text instead.
    private static func linkReferenceDefinitions(in source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: true)
            .filter { $0.wholeMatch(of: /\ {0,3}\[[^\]]+\]:\s*\S+.*/) != nil }
            .map(String.init)
    }
}
