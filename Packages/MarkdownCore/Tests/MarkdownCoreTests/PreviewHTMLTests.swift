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

@Test func previewMatchesBareWhenNoLanguageFence() {
    let source = """
    ``` 
    plain
    ```
    """
    #expect(PreviewHTML.render(source) == BareHTML.render(source))
}
