#if os(macOS)
import AppKit
import Testing
import MarkdownCore
@testable import SkinnyDip

/// Writes to a private pasteboard and reads every flavor back, the closest a
/// test gets to a paste. The paste matrix checks what destinations do with it.
@MainActor
struct ClipboardMacTests {
    private let pasteboard = NSPasteboard(name: .init("SkinnyDipTests.\(UUID().uuidString)"))

    @Test func richTextWritesHTMLAndMarkdownButNoRTF() throws {
        let payload = CopyAsRichText.payload(for: "# Notes\n\n- [x] done ☑\n")
        MacClipboard(pasteboard: pasteboard).write(payload)
        defer { pasteboard.releaseGlobally() }

        let html = try #require(pasteboard.data(forType: .html))
        #expect(String(decoding: html, as: UTF8.self) == payload.html)
        #expect(pasteboard.string(forType: .string) == "# Notes\n\n- [x] done ☑\n")
        #expect(pasteboard.string(forType: .skinnyDipMarkdown) == "# Notes\n\n- [x] done ☑\n")
        #expect(pasteboard.types?.contains(.rtf) == false)
        #expect(pasteboard.pasteboardItems?.count == 1)
    }

    @Test func plainTextWritesOnlyText() {
        MacClipboard(pasteboard: pasteboard).write(plainText: "<h2>Notes</h2>")
        defer { pasteboard.releaseGlobally() }

        #expect(pasteboard.string(forType: .string) == "<h2>Notes</h2>")
        #expect(pasteboard.data(forType: .html) == nil)
        #expect(pasteboard.data(forType: .skinnyDipMarkdown) == nil)
    }

    @Test func aNewCopyReplacesTheOldFlavors() {
        let clipboard = MacClipboard(pasteboard: pasteboard)
        clipboard.write(CopyAsRichText.payload(for: "Hello"))
        clipboard.write(plainText: "Hello")
        defer { pasteboard.releaseGlobally() }

        #expect(pasteboard.data(forType: .html) == nil)
    }
}
#endif
