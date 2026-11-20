import Testing
@testable import MarkdownCore

/// The Preview highlights the top-level block the Editor's caret is in. `PreviewBlocks`
/// maps a caret line to that block's `data-source-line` (ADR-0006 anchors).
struct PreviewBlocksTests {
    let source = """
    # Title

    First paragraph
    continues here.

    - one
    - two

    ```swift
    let x = 1
    ```

    | A | B |
    |---|---|
    | 1 | 2 |

    > quoted
    > more

    Last paragraph.
    """

    private var blocks: PreviewBlocks { PreviewBlocks(source: source) }

    @Test func headingLine() {
        #expect(blocks.blockLine(containing: 1) == 1)
    }

    @Test func everyLineOfAParagraphMapsToItsFirstLine() {
        #expect(blocks.blockLine(containing: 3) == 3)
        #expect(blocks.blockLine(containing: 4) == 3)
    }

    @Test func blankLinesBetweenBlocksMapToNothing() {
        #expect(blocks.blockLine(containing: 2) == nil)
        #expect(blocks.blockLine(containing: 5) == nil)
        #expect(blocks.blockLine(containing: 8) == nil)
    }

    @Test func listItemsMapToTheWholeList() {
        #expect(blocks.blockLine(containing: 6) == 6)
        #expect(blocks.blockLine(containing: 7) == 6)
    }

    @Test func fencedCodeIncludesItsFences() {
        #expect(blocks.blockLine(containing: 9) == 9)
        #expect(blocks.blockLine(containing: 10) == 9)
        #expect(blocks.blockLine(containing: 11) == 9)
        #expect(blocks.blockLine(containing: 12) == nil)
    }

    @Test func tableAndQuoteRows() {
        #expect(blocks.blockLine(containing: 13) == 13)
        #expect(blocks.blockLine(containing: 15) == 13)
        #expect(blocks.blockLine(containing: 17) == 17)
        #expect(blocks.blockLine(containing: 18) == 17)
    }

    @Test func lastBlockAndPastTheEnd() {
        #expect(blocks.blockLine(containing: 20) == 20)
        #expect(blocks.blockLine(containing: 21) == nil)
        #expect(blocks.blockLine(containing: 0) == nil)
    }

    @Test func looseListKeepsBlankLinesInside() {
        let loose = PreviewBlocks(source: "- one\n\n- two\n\nAfter")
        #expect(loose.blockLine(containing: 2) == 1)
        #expect(loose.blockLine(containing: 3) == 1)
        #expect(loose.blockLine(containing: 4) == nil)
        #expect(loose.blockLine(containing: 5) == 5)
    }

    @Test func blockLinesMatchPreviewAnchors() {
        let html = PreviewHTML.render(source)
        for line in blocks.ranges.map(\.lowerBound) {
            #expect(html.contains("data-source-line=\"\(line)\""))
        }
    }

    @Test func emptyDocumentHasNoBlocks() {
        #expect(PreviewBlocks(source: "").ranges.isEmpty)
        #expect(PreviewBlocks.empty.blockLine(containing: 1) == nil)
    }
}

@Test func renderDeliversHTMLWithMatchingBlocks() async throws {
    let parser = MarkdownParser(debounceNanoseconds: 10_000_000)
    let gate = PreviewRenderGate()
    await parser.render(source: "# Hi\n\nThere", options: .default) { render in
        Task { await gate.record(render) }
    }
    try await Task.sleep(nanoseconds: 100_000_000)
    let render = try #require(await gate.value)
    #expect(render.html.contains("There"))
    #expect(render.blocks.blockLine(containing: 3) == 3)
}

private actor PreviewRenderGate {
    private(set) var value: PreviewRender?
    func record(_ render: PreviewRender) { value = render }
}
