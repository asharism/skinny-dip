#if os(macOS)
import Foundation
import MarkdownCore

/// The three copy commands (ADR-0011): ⌘C, ⌘⇧C and ⌥⌘C.
enum CopyCommand: Equatable {
    /// The standard Copy: the selected Markdown, plain text only, nothing with no selection.
    case plain
    /// Bare HTML plus the Markdown; the whole document with no selection.
    case richText
    /// The Bare HTML as plain text; the whole document with no selection.
    case html
}

/// Single place that builds copy payloads for the menu, the editors' `copy(_:)`
/// overrides (WebKit and AppKit must not put styled HTML or RTF on the
/// pasteboard), the Preview, and app tests.
@MainActor
enum CopyWriter {
    static func richTextPayload(
        for source: CopySource,
        options: RenderOptions = RenderSettings.options()
    ) -> CopyPayload {
        CopyAsRichText.payload(for: source.markdown, selection: source.selection, options: options)
    }

    static func write(
        _ command: CopyCommand,
        markdown: String,
        selection: Range<String.Index>?,
        documentID: UUID? = nil,
        clipboard: any Clipboard = MacClipboard()
    ) {
        switch command {
        case .plain:
            writePlainSelection(markdown: markdown, selection: selection, documentID: documentID, clipboard: clipboard)
        case .richText:
            writeRichText(from: CopySource(markdown: markdown, selection: selection, documentID: documentID), clipboard: clipboard)
        case .html:
            writeHTML(markdown: markdown, selection: selection, documentID: documentID, clipboard: clipboard)
        }
    }

    /// ⌘C: the selected Markdown exactly as typed, as plain text only. With no
    /// selection the pasteboard is left alone and this returns false.
    @discardableResult
    static func writePlainSelection(
        markdown: String,
        selection: Range<String.Index>?,
        documentID: UUID? = nil,
        clipboard: any Clipboard = MacClipboard()
    ) -> Bool {
        guard let selection, !selection.isEmpty else { return false }
        clipboard.write(plainText: CopyAsMarkdown.text(for: markdown, selection: selection))
        CopyFeedback.post(.markdown, documentID: documentID)
        return true
    }

    static func writeRichText(from source: CopySource, clipboard: any Clipboard) {
        clipboard.write(richTextPayload(for: source))
        CopyFeedback.post(.richText, documentID: source.documentID)
    }

    static func writeRichText(markdown: String, selection: Range<String.Index>?, documentID: UUID? = nil) {
        writeRichText(from: CopySource(markdown: markdown, selection: selection, documentID: documentID), clipboard: MacClipboard())
    }

    /// Copy as Markdown, from the Copy split button: the selection, or the whole document.
    static func writeMarkdown(markdown: String, selection: Range<String.Index>?, documentID: UUID? = nil) {
        MacClipboard().write(plainText: CopyAsMarkdown.text(for: markdown, selection: selection))
        CopyFeedback.post(.markdown, documentID: documentID)
    }

    static func writeHTML(
        markdown: String,
        selection: Range<String.Index>?,
        documentID: UUID? = nil,
        clipboard: any Clipboard = MacClipboard()
    ) {
        clipboard.write(plainText: CopyAsHTML.text(
            for: markdown,
            selection: selection,
            options: RenderSettings.options()
        ))
        CopyFeedback.post(.html, documentID: documentID)
    }
}
#endif
