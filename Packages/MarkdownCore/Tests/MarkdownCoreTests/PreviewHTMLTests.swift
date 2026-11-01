import Testing
@testable import MarkdownCore

@Test func previewCodeBlockGetsDataLangOnlyOnPreviewPath() {
    let source = """
    ```swift
    let x = 1
    ```
    """
    #expect(PreviewHTML.render(source).contains("data-lang=\"swift\""))
    #expect(!BareHTML.render(source).contains("data-lang"))
}

@Test func previewMatchesBareWithSameRenderOptions() {
    let source = "# Title\n\n| a | b |\n|---|---|\n| 1 | 2 |\n"
    let options = RenderOptions(demotesHeadings: true, bordersTables: true, newlinesAsBreaks: true)
    let bare = BareHTML.render(source, options: options)
    let preview = PreviewHTML.render(source, options: options)
    #expect(preview == bare)
}

@Test func previewMatchesBareWhenNoLanguageFence() {
    let source = """
    ``` 
    plain
    ```
    """
    #expect(PreviewHTML.render(source) == BareHTML.render(source))
}
