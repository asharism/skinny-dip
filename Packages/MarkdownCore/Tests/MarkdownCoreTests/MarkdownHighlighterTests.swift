import Foundation
import Testing
@testable import MarkdownCore

/// Native Editor Backend highlighting (ADR-0010): spans come from swift-markdown's
/// source ranges, in UTF-16 offsets, so they index an `NSTextStorage` directly.
struct MarkdownHighlighterTests {
    /// The source text each span of `role` covers, in order.
    private func texts(_ source: String, _ role: HighlightRole) -> [String] {
        let string = source as NSString
        return highlightSpans(in: source)
            .filter { $0.role == role }
            .map { string.substring(with: $0.range) }
    }

    @Test func emptyInputHasNoSpans() {
        #expect(highlightSpans(in: "").isEmpty)
    }

    @Test func plainParagraphHasNoSpans() {
        #expect(highlightSpans(in: "just words\n").isEmpty)
    }

    @Test func atxHeading() {
        let source = "## Title here\n\nBody\n"
        #expect(texts(source, .heading) == ["## Title here"])
        #expect(texts(source, .marker) == ["##"])
    }

    @Test func setextHeadingUnderlineIsAMarker() {
        let source = "Title\n=====\n"
        #expect(texts(source, .heading) == ["Title\n====="])
        #expect(texts(source, .marker) == ["====="])
    }

    @Test func emphasisAndStrong() {
        let source = "a *soft* and **loud** b\n"
        #expect(texts(source, .emphasis) == ["*soft*"])
        #expect(texts(source, .strong) == ["**loud**"])
        #expect(texts(source, .marker) == ["*", "*", "**", "**"])
    }

    @Test func inlineCode() {
        let source = "run ``a ` b`` now\n"
        #expect(texts(source, .code) == ["``a ` b``"])
        #expect(texts(source, .marker) == ["``", "``"])
    }

    @Test func fencedCode() {
        let source = "```swift\nlet x = 1\n```\n"
        #expect(texts(source, .code) == ["```swift\nlet x = 1\n```"])
        #expect(texts(source, .marker) == ["```swift", "```"])
    }

    @Test func link() {
        let source = "see [the docs](https://example.com) ok\n"
        #expect(texts(source, .link) == ["[the docs](https://example.com)"])
        #expect(texts(source, .marker) == ["[", "](https://example.com)"])
    }

    @Test func blockQuote() {
        let source = "> one\n> two\n"
        #expect(texts(source, .quote) == ["> one\n> two"])
        #expect(texts(source, .marker) == [">", ">"])
    }

    @Test func listMarkers() {
        let source = "- one\n* two\n\n1. three\n10. four\n"
        #expect(texts(source, .marker) == ["-", "*", "1.", "10."])
    }

    @Test func taskListCheckboxIsAMarker() {
        let source = "- [x] done\n"
        #expect(texts(source, .marker) == ["-", "[x]"])
    }

    @Test func thematicBreak() {
        #expect(texts("a\n\n---\n", .marker) == ["---"])
    }

    @Test func spansAfterAnEmojiUseUTF16Offsets() {
        let source = "👋🏽 hi *there*\n"
        let span = highlightSpans(in: source).first { $0.role == .emphasis }
        // 👋🏽 is four UTF-16 units (two surrogate pairs) and eight UTF-8 bytes.
        #expect(span?.range == NSRange(location: 8, length: 7))
    }

    @Test func spansWithCRLFLineEndings() {
        let source = "# One\r\n\r\nsome **bold**\r\n"
        #expect(texts(source, .heading) == ["# One"])
        #expect(texts(source, .strong) == ["**bold**"])
        let strong = highlightSpans(in: source).first { $0.role == .strong }
        #expect(strong?.range.location == 14)
    }

    @Test func nestedSpansComeAfterTheirParent() {
        let source = "# Big *idea*\n"
        let roles = highlightSpans(in: source).map(\.role)
        #expect(roles == [.heading, .marker, .emphasis, .marker, .marker])
    }
}
