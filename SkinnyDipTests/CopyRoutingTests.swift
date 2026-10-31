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

    @Test func copyWriterRichTextHTMLHasNoStyleAttributes() {
        let markdown = "Hello **bold** world.\n"
        let payload = CopyWriter.richTextPayload(for: CopySource(markdown: markdown, selection: nil))

        #expect(payload.html.contains("<strong>bold</strong>"))
        #expect(!payload.html.contains("style="))
        #expect(payload.html.range(of: #"\bstyle\s*="#, options: .regularExpression) == nil)
    }
}
#endif
