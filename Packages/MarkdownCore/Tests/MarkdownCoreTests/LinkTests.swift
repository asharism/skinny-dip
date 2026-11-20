import MarkdownCore
import Testing

/// Links (#94): paste a URL over a selection, and ⌘K.
struct LinkTests {
    // MARK: singleURL

    @Test(arguments: [
        ("https://a.b/c?d=e#f", "https://a.b/c?d=e#f"),
        ("http://example.com", "http://example.com"),
        ("  https://example.com/x \n", "https://example.com/x"),
        ("HTTPS://Example.com", "HTTPS://Example.com"),
        ("https://en.wikipedia.org/wiki/Swift_(programming_language)", "https://en.wikipedia.org/wiki/Swift_(programming_language)"),
    ])
    func singleURLAccepts(_ text: String, _ url: String) {
        #expect(MarkdownEditing.singleURL(in: text) == url)
    }

    @Test(arguments: [
        "example.com",
        "https://a b",
        "mailto:x@y",
        "ftp://example.com/file",
        "https://a.b/one\nhttps://a.b/two",
        "https://",
        "https:///path",
        "see https://example.com",
        "",
        "   ",
    ])
    func singleURLRejects(_ text: String) {
        #expect(MarkdownEditing.singleURL(in: text) == nil)
    }

    // MARK: linkURL (what's on the pasteboard)

    @Test func linkURLFromPlainText() {
        #expect(MarkdownEditing.linkURL(in: PasteboardContents(plainText: "https://a.b/c\n")) == "https://a.b/c")
        #expect(MarkdownEditing.linkURL(in: PasteboardContents(plainText: "just words")) == nil)
        #expect(MarkdownEditing.linkURL(in: PasteboardContents()) == nil)
    }

    /// A link copied from a page, or an address bar that writes HTML: the
    /// HTML's text is just the URL, so the URL comes from the `<a href>`.
    @Test func linkURLFromHTMLWhoseTextIsTheURL() {
        let html = #"<meta charset="utf-8"><a href="https://a.b/c?d=1&amp;e=2">https://a.b/c?d=1&amp;e=2</a>"#
        #expect(MarkdownEditing.linkURL(in: PasteboardContents(html: html)) == "https://a.b/c?d=1&e=2")
        #expect(MarkdownEditing.linkURL(in: PasteboardContents(html: "<span>https://a.b/c</span>")) == "https://a.b/c")
    }

    /// A link with its own title is a link to paste, not a URL to wrap.
    @Test func linkURLIgnoresHTMLWithOtherText() {
        let html = #"<a href="https://a.b/c">A title</a>"#
        #expect(MarkdownEditing.linkURL(in: PasteboardContents(html: html, plainText: "A title")) == nil)
    }

    // MARK: pasteLink

    @Test func pasteLinkWrapsASingleLineSelection() {
        expectEdit({ MarkdownEditing.pasteLink($0, url: "https://a.b/c") }, from: "See «the docs» now", to: "See [the docs](https://a.b/c)| now")
        expectEdit({ MarkdownEditing.pasteLink($0, url: "https://a.b/c") }, from: "«👋🏽»", to: "[👋🏽](https://a.b/c)|")
        expectEdit({ MarkdownEditing.pasteLink($0, url: "https://a.b/c") }, from: "a\r\n«word»\r\nb", to: "a\r\n[word](https://a.b/c)|\r\nb")
    }

    @Test func pasteLinkDeclines() {
        let paste: (EditorState) -> TextEdit? = { MarkdownEditing.pasteLink($0, url: "https://a.b/c") }
        expectEdit(paste, from: "no |selection", to: nil)
        expectEdit(paste, from: "«two\nlines»", to: nil)
        expectEdit(paste, from: "«two\r\nlines»", to: nil)
        expectEdit(paste, from: "see «https://old.example/x»", to: nil)
        expectEdit(paste, from: "```\n«code»\n```", to: nil)
        expectEdit({ MarkdownEditing.pasteLink($0, url: "not a url") }, from: "«word»", to: nil)
    }

    @Test func pasteLinkEscapesUnbalancedBracketsInTheText() {
        let paste: (EditorState) -> TextEdit? = { MarkdownEditing.pasteLink($0, url: "https://a.b") }
        expectEdit(paste, from: "«a]b»", to: #"[a\]b](https://a.b)|"#)
        expectEdit(paste, from: "«a[b»", to: #"[a\[b](https://a.b)|"#)
        // Balanced brackets are fine in link text and stay as typed.
        expectEdit(paste, from: "«a [b] c»", to: "[a [b] c](https://a.b)|")
        // Already escaped stays as is.
        expectEdit(paste, from: #"«a\]b»"#, to: #"[a\]b](https://a.b)|"#)
    }

    @Test func pasteLinkWrapsAURLWithParenthesesInAngleBrackets() {
        let paste: (EditorState) -> TextEdit? = { MarkdownEditing.pasteLink($0, url: "https://a.b/x)y") }
        expectEdit(paste, from: "«word»", to: "[word](<https://a.b/x)y>)|")
        expectEdit({ MarkdownEditing.pasteLink($0, url: "https://w.org/S_(p)") }, from: "«S»", to: "[S](<https://w.org/S_(p)>)|")
    }

    // MARK: insertLink (⌘K)

    @Test func insertLinkTable() {
        let url = "https://a.b/c"
        // text, clipboard URL: [text](url), caret after.
        expectEdit({ MarkdownEditing.insertLink($0, clipboardURL: url) }, from: "a «word» b", to: "a [word](https://a.b/c)| b")
        // text, no URL: caret in the parens.
        expectEdit({ MarkdownEditing.insertLink($0, clipboardURL: nil) }, from: "a «word» b", to: "a [word](|) b")
        // text that is a URL: it becomes the destination, caret in the brackets.
        expectEdit({ MarkdownEditing.insertLink($0, clipboardURL: url) }, from: "«https://x.y/z»", to: "[|](https://x.y/z)")
        expectEdit({ MarkdownEditing.insertLink($0, clipboardURL: nil) }, from: "«https://x.y/z»", to: "[|](https://x.y/z)")
        // empty, clipboard URL.
        expectEdit({ MarkdownEditing.insertLink($0, clipboardURL: url) }, from: "a |b", to: "a [|](https://a.b/c)b")
        // empty, no URL.
        expectEdit({ MarkdownEditing.insertLink($0, clipboardURL: nil) }, from: "a |b", to: "a [|]()b")
    }

    @Test func insertLinkEscapesAndAroundEmoji() {
        expectEdit({ MarkdownEditing.insertLink($0, clipboardURL: "https://a.b/(x") }, from: "👋🏽«a]»", to: #"👋🏽[a\]](<https://a.b/(x>)|"#)
        expectEdit({ MarkdownEditing.insertLink($0, clipboardURL: nil) }, from: "👋🏽«a»👋🏽", to: "👋🏽[a](|)👋🏽")
    }

    @Test func insertLinkDeclinesAcrossLinesAndInCode() {
        expectEdit({ MarkdownEditing.insertLink($0, clipboardURL: nil) }, from: "«a\nb»", to: nil)
        expectEdit({ MarkdownEditing.insertLink($0, clipboardURL: nil) }, from: "~~~\n|\n~~~", to: nil)
    }
}
