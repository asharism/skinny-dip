import Foundation
import Testing
import MarkdownCore

struct PasteAsMarkdownTests {
    @Test func ownCopyPastesItsExactMarkdown() {
        let contents = PasteboardContents(
            skinnyDipMarkdown: "# Notes\n\n- a\n",
            html: "<h2>Notes</h2><ul><li>a</li></ul>",
            plainText: "# Notes\n\n- a\n"
        )
        #expect(PasteAsMarkdown.text(for: contents) == "# Notes\n\n- a\n")
    }

    @Test func richTextFromOtherAppsIsConverted() {
        let contents = PasteboardContents(html: "<p>Hello <b>world</b></p>", plainText: "Hello world")
        #expect(PasteAsMarkdown.text(for: contents) == "Hello **world**")
    }

    @Test func plainTextOnlyPastesUnchanged() {
        let contents = PasteboardContents(plainText: "a*b_c\r\nnext")
        #expect(PasteAsMarkdown.text(for: contents) == "a*b_c\nnext")
    }

    @Test func htmlWithNothingConvertibleFallsBackToPlainText() {
        let contents = PasteboardContents(html: "<img src=\"https://example.com/a.png\">", plainText: "a.png")
        #expect(PasteAsMarkdown.text(for: contents) == "a.png")
    }

    @Test func emptyPasteboardPastesNothing() {
        #expect(PasteAsMarkdown.text(for: PasteboardContents()) == nil)
        #expect(PasteAsMarkdown.text(for: PasteboardContents(skinnyDipMarkdown: "", plainText: " ")) == nil)
    }

    @Test func codeEditorCopyPastesPlainText() {
        // VS Code's HTML flavor: one monospace `white-space: pre` wrapper.
        let html = """
        <meta charset='utf-8'><div style="color: #cccccc;background-color: #1f1f1f;font-family: Menlo, Monaco, 'Courier New', monospace;font-weight: normal;font-size: 12px;line-height: 18px;white-space: pre;"><div><span style="color: #569cd6;font-weight: bold;"># Title</span></div><div><span style="color: #cccccc;">- item_one</span></div></div>
        """
        let contents = PasteboardContents(html: html, plainText: "# Title\n- item_one")
        #expect(PasteAsMarkdown.text(for: contents) == "# Title\n- item_one")
    }

    @Test func lonePreCopyPastesPlainText() {
        let contents = PasteboardContents(html: "<pre>let a = 1</pre>", plainText: "let a = 1")
        #expect(PasteAsMarkdown.text(for: contents) == "let a = 1")
    }

    @Test func pasteAndMatchStyleIsAlwaysPlain() {
        let contents = PasteboardContents(
            skinnyDipMarkdown: "**a**",
            html: "<b>a</b>",
            plainText: "a"
        )
        #expect(PasteAsMarkdown.plainText(for: contents) == "a")
        #expect(PasteAsMarkdown.plainText(for: PasteboardContents(html: "<b>a</b>")) == nil)
    }
}

struct HTMLToMarkdownTests {
    @Test func escapedTextRendersAsTheSameText() {
        let html = "<p>1. not a list</p><p># not a heading</p><p>a *star* and _under_ and [link]</p>"
        let rendered = BareHTML.render(HTMLToMarkdown.convert(html), options: .plain)
        #expect(rendered == "<p>1. not a list</p>\n<p># not a heading</p>\n<p>a *star* and _under_ and [link]</p>")
    }

    @Test func windowsFragmentHeaderIsIgnored() {
        let html = "Version:0.9\r\nStartHTML:0000000105\r\nEndHTML:0000000200\r\n<html><body><!--StartFragment--><p>Hi</p><!--EndFragment--></body></html>"
        #expect(HTMLToMarkdown.convert(html) == "Hi")
    }

    @Test func styledPlainTextDetection() {
        #expect(HTMLToMarkdown.isStyledPlainText("<pre>code</pre>"))
        #expect(HTMLToMarkdown.isStyledPlainText("<meta charset=utf-8><div style=\"white-space: pre\">x</div>"))
        #expect(HTMLToMarkdown.isStyledPlainText("<div style=\"font-family: Menlo, monospace\">x</div>"))
        #expect(!HTMLToMarkdown.isStyledPlainText("<div style=\"font-family: Calibri, monospace\">x</div>"))
        #expect(!HTMLToMarkdown.isStyledPlainText("<p>prose</p><pre>code</pre>"))
        #expect(!HTMLToMarkdown.isStyledPlainText("<h1>Title</h1>"))
    }
}

struct PasteboardHTMLTests {
    @Test func decodesUTF8AndUTF16() {
        #expect(PasteboardHTML.decode(Data("<p>café</p>".utf8)) == "<p>café</p>")
        var utf16 = Data([0xFF, 0xFE])
        utf16.append("<p>café</p>".data(using: .utf16LittleEndian)!)
        #expect(PasteboardHTML.decode(utf16) == "<p>café</p>")
    }

    @Test func decodesALegacyCharset() {
        let data = "<meta charset=windows-1252><p>café</p>".data(using: .windowsCP1252)!
        #expect(PasteboardHTML.decode(data) == "<meta charset=windows-1252><p>café</p>")
    }

    @Test func readsTheMainResourceOfAWebArchive() throws {
        let archive: [String: Any] = [
            "WebMainResource": [
                "WebResourceData": Data("<p>From <b>Safari</b></p>".utf8),
                "WebResourceMIMEType": "text/html",
                "WebResourceTextEncodingName": "UTF-8",
                "WebResourceURL": "https://example.com/",
            ],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0)
        #expect(PasteboardHTML.fromWebArchive(data) == "<p>From <b>Safari</b></p>")
        #expect(PasteboardHTML.fromWebArchive(Data("nope".utf8)) == nil)
    }
}
