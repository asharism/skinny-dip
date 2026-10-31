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
        // P1b: not implemented yet. SelectionCopyTests are expected to fail.
        CopyPayload(html: "", plainText: "")
    }
}
