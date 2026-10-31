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
#endif
