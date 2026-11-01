import Testing
import MarkdownCore

/// Sources mark the selection with « and »; a source without markers copies the
/// whole document. Expected HTML is the body only; `wrapped` adds the document
/// wrapper every payload carries.
struct CopyAsRichTextTests {
    @Test func wholeDocumentCopiesSourceAndWrappedHTML() {
        let payload = copy("# Notes\n\nHello\n")
        #expect(payload.plainText == "# Notes\n\nHello\n")
        #expect(payload.html == wrapped("<h2>Notes</h2>\n<p>Hello</p>"))
    }

    @Test func emptySelectionCopiesWholeDocument() {
        let payload = copy("Hello «»world")
        #expect(payload.plainText == "Hello world")
        #expect(payload.html == wrapped("<p>Hello world</p>"))
    }

    @Test func midParagraphSelectionBecomesItsOwnParagraph() {
        let payload = copy("The quick «brown fox» jumps")
        #expect(payload.plainText == "brown fox")
        #expect(payload.html == wrapped("<p>brown fox</p>"))
    }

    @Test func selectedListItemsKeepTheirNumbers() {
        let payload = copy("1. one\n«2. two\n3. three»\n")
        #expect(payload.plainText == "2. two\n3. three")
        #expect(payload.html == wrapped("<ol start=\"2\">\n<li>two</li>\n<li>three</li>\n</ol>"))
    }

    @Test func referenceLinksResolveAgainstDefinitionsOutsideTheSelection() {
        let payload = copy("«Read [the docs][d].»\n\n[d]: https://docs.example.com\n")
        #expect(payload.plainText == "Read [the docs][d].")
        #expect(payload.html == wrapped("<p>Read <a href=\"https://docs.example.com\">the docs</a>.</p>"))
    }

    @Test func selectionCuttingThroughMarkupCopiesTheMarkupAsText() {
        let payload = copy("Some **«bold** text»")
        #expect(payload.plainText == "bold** text")
        #expect(payload.html == wrapped("<p>bold** text</p>"))
    }

    @Test func selectionUsesTheGivenOptions() {
        let payload = copy("«# Title»", options: .plain)
        #expect(payload.html == wrapped("<h1>Title</h1>"))
    }

    // MARK: Helpers

    private func copy(_ marked: String, options: RenderOptions = .default) -> CopyPayload {
        guard let open = marked.firstIndex(of: "«"), let close = marked.firstIndex(of: "»") else {
            return CopyAsRichText.payload(for: marked, options: options)
        }
        let before = marked[..<open]
        let selected = marked[marked.index(after: open)..<close]
        let after = marked[marked.index(after: close)...]
        let source = String(before + selected + after)
        let start = source.index(source.startIndex, offsetBy: before.count)
        let end = source.index(start, offsetBy: selected.count)
        return CopyAsRichText.payload(for: source, selection: start..<end, options: options)
    }

    private func wrapped(_ body: String) -> String {
        "<html><head><meta charset=\"utf-8\"></head><body>\n\(body)\n</body></html>"
    }
}
