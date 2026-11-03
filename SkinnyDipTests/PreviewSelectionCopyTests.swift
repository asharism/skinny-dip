#if os(macOS)
import AppKit
import Testing
import WebKit
import MarkdownCore
@testable import SkinnyDip

/// ⌘C in the Preview with a selection copies that part of the Markdown Source
/// (whole top-level blocks), through the real `preview.html`.
@MainActor
struct PreviewSelectionCopyTests {
    private static let markdown = """
    # Title

    First paragraph.

    - one
    - two

    Last paragraph.
    """

    @Test func noSelectionCopiesTheWholeDocument() async throws {
        let webView = try await Self.loadedPreview()
        #expect(await webView.selectedSourceRange(in: Self.markdown) == nil)
    }

    @Test func partOfAParagraphCopiesThatParagraph() async throws {
        let webView = try await Self.loadedPreview()
        try await Self.select(webView, """
            const text = document.querySelectorAll("#content > p")[0].firstChild;
            range.setStart(text, 2); range.setEnd(text, 7);
            """)
        let range = try #require(await webView.selectedSourceRange(in: Self.markdown))
        #expect(String(Self.markdown[range]) == "First paragraph.")
    }

    @Test func aDragAcrossBlocksCopiesEachOfThem() async throws {
        let webView = try await Self.loadedPreview()
        try await Self.select(webView, """
            range.setStart(document.querySelector("#content > p").firstChild, 3);
            range.setEnd(document.querySelector("#content li").firstChild, 1);
            """)
        let range = try #require(await webView.selectedSourceRange(in: Self.markdown))
        #expect(String(Self.markdown[range]) == "First paragraph.\n\n- one\n- two")
    }

    /// A triple-click ends at offset 0 of the next block; that block isn't copied.
    @Test func aTripleClickDoesNotSpillIntoTheNextBlock() async throws {
        let webView = try await Self.loadedPreview()
        try await Self.select(webView, """
            const p = document.querySelector("#content > p");
            range.setStart(p.firstChild, 0);
            range.setEnd(document.querySelector("#content ul"), 0);
            """)
        let range = try #require(await webView.selectedSourceRange(in: Self.markdown))
        #expect(String(Self.markdown[range]) == "First paragraph.")
    }

    private static func select(_ webView: WKWebView, _ body: String) async throws {
        _ = try await webView.callAsyncJavaScript(
            "const range = document.createRange();\n\(body)\nconst s = getSelection(); s.removeAllRanges(); s.addRange(range);",
            contentWorld: .page
        )
    }

    private static func loadedPreview() async throws -> PreviewWebView {
        let webView = PreviewWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), configuration: WKWebViewConfiguration())
        let page = try #require(WebBundleResources.page(named: "preview.html"))
        webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        for _ in 0..<100 {
            if (try? await webView.evaluateJavaScript("typeof selectedSourceLines")) as? String == "function" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        _ = try await webView.callAsyncJavaScript(
            "setScrollSync(false); render(html);",
            arguments: ["html": PreviewHTML.render(markdown)],
            contentWorld: .page
        )
        return webView
    }
}
#endif
