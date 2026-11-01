/// Resolves what text ⌘V should insert from pasteboard flavors (testable without AppKit).
public struct PasteboardContents: Sendable, Equatable {
    public var skinnyDipMarkdown: String?
    public var html: String?
    public var plainText: String?

    public init(
        skinnyDipMarkdown: String? = nil,
        html: String? = nil,
        plainText: String? = nil
    ) {
        self.skinnyDipMarkdown = skinnyDipMarkdown
        self.html = html
        self.plainText = plainText
    }
}

public enum PasteAsMarkdown {
    /// Paste as Markdown (⌘V): Skinny Dip flavor, else HTML conversion, else plain text.
    public static func insertText(from contents: PasteboardContents) -> String? {
        if let markdown = contents.skinnyDipMarkdown, !markdown.isEmpty {
            return markdown
        }
        if let html = contents.html, !html.isEmpty {
            return HTMLToMarkdown.convert(html)
        }
        if let plain = contents.plainText {
            return plain
        }
        return nil
    }

    /// Paste and Match Style (⌥⇧⌘V): plain text only, never converted.
    public static func plainInsertText(from contents: PasteboardContents) -> String? {
        contents.plainText
    }
}
