#if os(macOS)
import AppKit
import MarkdownCore

struct MacClipboard: Clipboard {
    /// Tests pass a private named pasteboard so they never touch the user's clipboard.
    var pasteboard: NSPasteboard = .general

    func write(_ payload: CopyPayload) {
        // One item with several flavors: each destination picks the richest one it
        // understands. No RTF, because NSAttributedString(html:) bakes in fonts.
        let item = NSPasteboardItem()
        item.setData(Data(payload.html.utf8), forType: .html)
        item.setString(payload.plainText, forType: .string)
        item.setString(payload.plainText, forType: .skinnyDipMarkdown)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    func write(plainText: String) {
        pasteboard.clearContents()
        pasteboard.setString(plainText, forType: .string)
    }
}

extension NSPasteboard.PasteboardType {
    static let skinnyDipMarkdown = Self(ClipboardType.skinnyDipMarkdown)
}

extension NSPasteboard.PasteboardType {
    static let webArchive = Self("com.apple.webarchive")
}

extension NSPasteboard {
    /// Cheap enough for menu validation: looks at the flavors, converts nothing.
    var canPasteFromPasteboard: Bool {
        availableType(from: [.skinnyDipMarkdown, .string, .html, .webArchive, .rtf]) != nil
    }

    /// The flavors Paste as Markdown chooses between (`PasteAsMarkdown`).
    var pasteContents: PasteboardContents {
        let html = data(forType: .html).flatMap(PasteboardHTML.decode)
            ?? data(forType: .webArchive).flatMap(PasteboardHTML.fromWebArchive)
        return PasteboardContents(
            skinnyDipMarkdown: string(forType: .skinnyDipMarkdown),
            html: html,
            plainText: plainText
        )
    }

    /// The plain-text flavor, or the text of an RTF-only copy (TextEdit).
    private var plainText: String? {
        if let plain = string(forType: .string), !plain.isEmpty {
            return plain
        }
        if let data = data(forType: .rtf),
           let text = NSAttributedString(rtf: data, documentAttributes: nil)?.string,
           !text.isEmpty {
            return text
        }
        return nil
    }
}
#endif
