import Testing
import MarkdownCore

/// Copy as Markdown and Copy as HTML, which both put plain text on the clipboard.
/// Sources mark the selection with « and » as in `CopyAsRichTextTests`.
struct CopyAsTextTests {
    @Test func markdownCopiesWholeDocumentWithoutSelection() {
        #expect(markdown("# Notes\n\nHello\n") == "# Notes\n\nHello\n")
    }

    @Test func markdownCopiesWholeDocumentForEmptySelection() {
        #expect(markdown("Hello «»world") == "Hello world")
    }

    @Test func markdownCopiesTheExactSelection() {
        #expect(markdown("Some **«bold** text»") == "bold** text")
    }

    @Test func htmlIsBareHTMLWithoutTheDocumentWrapper() {
        #expect(html("# Notes\n\nHello\n") == "<h2>Notes</h2>\n<p>Hello</p>")
    }

    @Test func htmlForEmptySelectionIsTheWholeDocument() {
        #expect(html("Hello «»world") == "<p>Hello world</p>")
    }

    @Test func htmlForSelectionMatchesSelectionCopy() {
        #expect(html("«Read [the docs][d].»\n\n[d]: https://docs.example.com\n")
            == "<p>Read <a href=\"https://docs.example.com\">the docs</a>.</p>")
    }

    @Test func htmlUsesTheGivenOptions() {
        #expect(html("«# Title»", options: .plain) == "<h1>Title</h1>")
    }

    // MARK: Helpers

    private func markdown(_ marked: String) -> String {
        let (source, selection) = unmark(marked)
        return CopyAsMarkdown.text(for: source, selection: selection)
    }

    private func html(_ marked: String, options: RenderOptions = .default) -> String {
        let (source, selection) = unmark(marked)
        return CopyAsHTML.text(for: source, selection: selection, options: options)
    }

    private func unmark(_ marked: String) -> (String, Range<String.Index>?) {
        guard let open = marked.firstIndex(of: "«"), let close = marked.firstIndex(of: "»") else {
            return (marked, nil)
        }
        let before = marked[..<open]
        let selected = marked[marked.index(after: open)..<close]
        let after = marked[marked.index(after: close)...]
        let source = String(before + selected + after)
        let start = source.index(source.startIndex, offsetBy: before.count)
        let end = source.index(start, offsetBy: selected.count)
        return (source, start..<end)
    }
}
