import Testing
@testable import MarkdownCore

/// A Preview selection is reported as the `data-source-line` of the first and last
/// top-level blocks it touches; the copy covers those blocks' Markdown Source whole.
struct PreviewSelectionTests {
    let source = """
    # Title

    First paragraph
    continues here.

    - one
    - two

    | A | B |
    |---|---|
    | 1 | 2 |

    Last paragraph.
    """

    private func copied(_ first: Int, _ last: Int, in text: String? = nil) -> String? {
        let text = text ?? source
        return PreviewSelection.range(in: text, firstBlockLine: first, lastBlockLine: last).map { String(text[$0]) }
    }

    @Test func oneBlockCoversAllItsLines() {
        #expect(copied(3, 3) == "First paragraph\ncontinues here.")
    }

    @Test func severalBlocksIncludeTheBlankLinesBetween() {
        #expect(copied(6, 9) == "- one\n- two\n\n| A | B |\n|---|---|\n| 1 | 2 |")
    }

    @Test func linesAreReorderedWhenReportedBackwards() {
        #expect(copied(13, 1) == source)
    }

    @Test func aLineThatStartsNoBlockIsIgnored() {
        #expect(copied(4, 4) == nil)
        #expect(copied(99, 99) == nil)
    }

    @Test func theCopyRendersLikeAnEditorSelection() throws {
        let range = try #require(PreviewSelection.range(in: source, firstBlockLine: 6, lastBlockLine: 6))
        let payload = CopyAsRichText.payload(for: source, selection: range)
        #expect(payload.plainText == "- one\n- two")
        #expect(payload.html.contains("<ul>"))
        #expect(!payload.html.contains("data-source-line"))
    }

    @Test func linkReferencesStillResolve() throws {
        let text = "See [docs][d].\n\nOther.\n\n[d]: https://example.com\n"
        let range = try #require(PreviewSelection.range(in: text, firstBlockLine: 1, lastBlockLine: 1))
        #expect(CopyAsRichText.payload(for: text, selection: range).html.contains("href=\"https://example.com\""))
    }

    @Test func crlfLineEndingsStayOutOfTheRange() {
        #expect(copied(1, 1, in: "Hello\r\n\r\nWorld\r\n") == "Hello")
    }
}
