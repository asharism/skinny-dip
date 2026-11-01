#if os(macOS)
import Foundation
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
        CopyFeedback.post(.richText, documentID: source.documentID)
    }

    static func writeRichText(markdown: String, selection: Range<String.Index>?, documentID: UUID? = nil) {
        writeRichText(from: CopySource(markdown: markdown, selection: selection, documentID: documentID), clipboard: MacClipboard())
    }

    static func writeMarkdown(markdown: String, selection: Range<String.Index>?, documentID: UUID? = nil) {
        MacClipboard().write(plainText: CopyAsMarkdown.text(for: markdown, selection: selection))
        CopyFeedback.post(.markdown, documentID: documentID)
    }

    static func writeHTML(markdown: String, selection: Range<String.Index>?, documentID: UUID? = nil) {
        MacClipboard().write(plainText: CopyAsHTML.text(
            for: markdown,
            selection: selection,
            options: RenderSettings.options()
        ))
        CopyFeedback.post(.html, documentID: documentID)
    }
}
#endif
