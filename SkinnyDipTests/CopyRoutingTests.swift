#if os(macOS)
import AppKit
import Testing
import MarkdownCore
@testable import SkinnyDip

/// Issue #4 acceptance: Copy as Rich Text (menu ⌘C and editor `copy(_:)`) must put
/// Bare HTML, plain Markdown, and the private flavor on the pasteboard — never RTF
/// or inline `style`. Both copy paths call `CopyWriter`; these tests exercise that
/// helper with `MacClipboard` on a private pasteboard (same as production writes).
@MainActor
struct CopyRoutingTests {
    private let pasteboard = NSPasteboard(name: .init("SkinnyDipTests.\(UUID().uuidString)"))

    @Test func copyWriterRichTextPasteboardFlavorsMatchAcceptance() throws {
        let markdown = "# Notes\n\n- [x] done ☑\n"
        let source = CopySource(markdown: markdown, selection: nil)
        CopyWriter.writeRichText(from: source, clipboard: MacClipboard(pasteboard: pasteboard))
        defer { pasteboard.releaseGlobally() }

        let payload = CopyWriter.richTextPayload(for: source)
        let html = try #require(pasteboard.data(forType: .html))
        #expect(String(decoding: html, as: UTF8.self) == payload.html)
        #expect(pasteboard.string(forType: .string) == markdown)
        #expect(pasteboard.string(forType: .skinnyDipMarkdown) == markdown)
        #expect(pasteboard.types?.contains(.rtf) == false)
        #expect(pasteboard.pasteboardItems?.count == 1)
    }

    /// ADR-0011: ⌘C is the standard Copy, the selected Markdown as plain text only.
    @Test func plainCopyWritesOnlyPlainText() throws {
        defer { pasteboard.releaseGlobally() }
        let markdown = "Intro\n\n**bold** text\n"
        let selection = try #require(markdown.range(of: "**bold** text"))
        let wrote = CopyWriter.writePlainSelection(
            markdown: markdown,
            selection: selection,
            clipboard: MacClipboard(pasteboard: pasteboard)
        )
        #expect(wrote)
        #expect(pasteboard.onlyFlavors == [.string])
        #expect(pasteboard.string(forType: .string) == "**bold** text")
        #expect(pasteboard.data(forType: .html) == nil)
        #expect(pasteboard.data(forType: .rtf) == nil)
        #expect(pasteboard.string(forType: .skinnyDipMarkdown) == nil)
        // Pasting it back into Skinny inserts the text as-is, through the plain-text path.
        #expect(PasteAsMarkdown.text(for: pasteboard.pasteContents) == "**bold** text")
    }

    @Test func plainCopyWithNoSelectionLeavesPasteboardUntouched() throws {
        defer { pasteboard.releaseGlobally() }
        let markdown = "Some **text**\n"
        let clipboard = MacClipboard(pasteboard: pasteboard)
        clipboard.write(plainText: "before")

        #expect(!CopyWriter.writePlainSelection(markdown: markdown, selection: nil, clipboard: clipboard))
        #expect(pasteboard.string(forType: .string) == "before")

        let empty = markdown.startIndex..<markdown.startIndex
        #expect(!CopyWriter.writePlainSelection(markdown: markdown, selection: empty, clipboard: clipboard))
        #expect(pasteboard.string(forType: .string) == "before")
    }

    /// ⌘⇧C keeps the old ⌘C fallback: no selection copies the whole document.
    @Test func richTextCopyWithNoSelectionCopiesWholeDocument() throws {
        defer { pasteboard.releaseGlobally() }
        let markdown = "# Title\n\nHello **bold** world.\n"
        CopyWriter.write(.richText, markdown: markdown, selection: nil, clipboard: MacClipboard(pasteboard: pasteboard))

        let html = try #require(pasteboard.data(forType: .html)).utf8String
        #expect(html.contains("<strong>bold</strong>"))
        #expect(html.contains("Title"))
        #expect(pasteboard.string(forType: .string) == markdown)
        #expect(pasteboard.string(forType: .skinnyDipMarkdown) == markdown)
    }

    @Test func copyWriterRichTextHTMLHasNoStyleAttributes() {
        let markdown = "Hello **bold** world.\n"
        let payload = CopyWriter.richTextPayload(for: CopySource(markdown: markdown, selection: nil))

        #expect(payload.html.contains("<strong>bold</strong>"))
        #expect(!payload.html.contains("style="))
        #expect(payload.html.range(of: #"\bstyle\s*="#, options: .regularExpression) == nil)
    }
}

private extension Data {
    var utf8String: String { String(decoding: self, as: UTF8.self) }
}

extension NSPasteboard {
    /// The flavors actually written, as one item. `types` also lists AppKit's
    /// legacy alias `NSStringPboardType` for plain text, which no copy writes.
    var onlyFlavors: [NSPasteboard.PasteboardType]? {
        guard let items = pasteboardItems, items.count == 1 else { return nil }
        return items[0].types
    }
}
#endif
