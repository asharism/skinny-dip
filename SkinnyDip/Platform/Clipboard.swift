import MarkdownCore

/// Where the copy commands put their output. Each platform writes its own
/// pasteboard (`Clipboard+Mac.swift`, later `Clipboard+iOS.swift`); the
/// content always comes from MarkdownCore.
protocol Clipboard {
    /// Copy as Rich Text: Bare HTML plus the Markdown Source, never RTF (ADR-0001).
    func write(_ payload: CopyPayload)
    /// Copy as Markdown and Copy as HTML: plain text only.
    func write(plainText: String)
}

enum ClipboardType {
    /// A private flavor carrying the Markdown Source of a Copy as Rich Text, so a
    /// paste back into Skinny Dip can take the Markdown instead of converting HTML.
    static let skinnyDipMarkdown = "com.hitesh.SkinnyDip.markdown"
}
