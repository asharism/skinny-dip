#if os(macOS)
import AppKit
import Testing
import WebKit
import MarkdownCore
@testable import SkinnyDip

/// The Preview tints the top-level block the Editor's caret is in, through the real
/// `preview.html` and the coordinator that pushes `highlightBlock(line)`.
@MainActor
struct PreviewCurrentBlockTests {
    private static let markdown = """
    # Title

    First paragraph
    continues here.

    - one
    - two

    Last paragraph.
    """

    @Test func caretLineTintsItsBlockOnly() async throws {
        let (webView, coordinator) = try await Self.loadedPreview()
        let blocks = PreviewBlocks(source: Self.markdown)
        coordinator.highlightLine = blocks.blockLine(containing: 7)
        await coordinator.pushChrome()
        #expect(try await Self.highlighted(webView) == ["6"])

        coordinator.highlightLine = blocks.blockLine(containing: 4)
        await coordinator.pushChrome()
        #expect(try await Self.highlighted(webView) == ["3"])
    }

    @Test func blankLineClearsTheTint() async throws {
        let (webView, coordinator) = try await Self.loadedPreview()
        coordinator.highlightLine = 3
        await coordinator.pushChrome()
        coordinator.highlightLine = PreviewBlocks(source: Self.markdown).blockLine(containing: 5)
        await coordinator.pushChrome()
        #expect(try await Self.highlighted(webView).isEmpty)
    }

    @Test func tintSurvivesARender() async throws {
        let (webView, coordinator) = try await Self.loadedPreview()
        coordinator.highlightLine = 9
        await coordinator.pushChrome()
        _ = try await webView.callAsyncJavaScript(
            "render(html)",
            arguments: ["html": PreviewHTML.render(Self.markdown + "\n")],
            contentWorld: .page
        )
        #expect(try await Self.highlighted(webView) == ["9"])
    }

    /// The tint is background and shadow only: no block moves when it appears.
    @Test func tintDoesNotMoveAnything() async throws {
        let (webView, coordinator) = try await Self.loadedPreview()
        let tops = "return Array.from(document.querySelectorAll('#content > *')).map((el) => el.getBoundingClientRect().top)"
        let before = try await webView.callAsyncJavaScript(tops, contentWorld: .page) as? [Double]
        coordinator.highlightLine = 3
        await coordinator.pushChrome()
        let after = try await webView.callAsyncJavaScript(tops, contentWorld: .page) as? [Double]
        #expect(before != nil)
        #expect(before == after)
    }

    private static func highlighted(_ webView: WKWebView) async throws -> [String] {
        let lines = try await webView.callAsyncJavaScript(
            "return Array.from(document.querySelectorAll('.current-block')).map((el) => el.getAttribute('data-source-line'))",
            contentWorld: .page
        )
        return lines as? [String] ?? []
    }

    private static func loadedPreview() async throws -> (PreviewWebView, PreviewView.Coordinator) {
        let coordinator = PreviewView.Coordinator()
        coordinator.scrollSync = false
        let webView = PreviewWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), configuration: WKWebViewConfiguration())
        coordinator.webView = webView
        let page = try #require(WebBundleResources.page(named: "preview.html"))
        webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        for _ in 0..<100 {
            if (try? await webView.evaluateJavaScript("typeof highlightBlock")) as? String == "function" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        _ = try await webView.callAsyncJavaScript(
            "setScrollSync(false); render(html);",
            arguments: ["html": PreviewHTML.render(markdown)],
            contentWorld: .page
        )
        return (webView, coordinator)
    }
}
#endif
