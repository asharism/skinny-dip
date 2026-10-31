#if os(macOS)
import MarkdownCore

/// Single place that builds copy payloads for the menu, the editor's `copy(_:)`
/// override (WebKit must not put styled HTML on the pasteboard), and app tests.
@MainActor
enum CopyWriter {
    static func richTextPayload(
        for source: CopySource,
        options: RenderOptions = RenderSettings.options()
    ) -> CopyPayload {
        CopyAsRichText.payload(for: source.markdown, selection: source.selection, options: options)
    }

    static func writeRichText(from source: CopySource, clipboard: any Clipboard) {
        clipboard.write(richTextPayload(for: source))
    }

    static func writeRichText(markdown: String, selection: Range<String.Index>?) {
        writeRichText(from: CopySource(markdown: markdown, selection: selection), clipboard: MacClipboard())
    }

    static func writeMarkdown(markdown: String, selection: Range<String.Index>?) {
        MacClipboard().write(plainText: CopyAsMarkdown.text(for: markdown, selection: selection))
    }

    static func writeHTML(markdown: String, selection: Range<String.Index>?) {
        MacClipboard().write(plainText: CopyAsHTML.text(
            for: markdown,
            selection: selection,
            options: RenderSettings.options()
        ))
    }
}
#endif
