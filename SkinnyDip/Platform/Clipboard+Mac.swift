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

extension NSPasteboard {
    var canPasteFromPasteboard: Bool {
        editorPasteText() != nil
    }

    /// Text for ⌘V. Copies made in Skinny Dip keep their Markdown flavor.
    /// Rich text from other apps uses the plain-text flavor, then RTF, then HTML.
    func editorPasteText() -> String? {
        if let markdown = string(forType: .skinnyDipMarkdown), !markdown.isEmpty {
            return markdown
        }
        if let plain = string(forType: .string), !plain.isEmpty {
            return plain
        }
        if let values = readObjects(forClasses: [NSString.self], options: nil) as? [String],
           let first = values.first, !first.isEmpty {
            return first
        }
        if let data = data(forType: .rtf),
           let text = NSAttributedString(rtf: data, documentAttributes: nil)?.string,
           !text.isEmpty {
            return text
        }
        if let data = data(forType: .html),
           let text = NSAttributedString(html: data, options: [:], documentAttributes: nil)?.string {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}
#endif
