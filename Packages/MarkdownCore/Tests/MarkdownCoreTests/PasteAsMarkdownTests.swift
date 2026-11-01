import Testing
@testable import MarkdownCore

@Test func pastePrefersSkinnyDipMarkdownOverHTML() {
    let contents = PasteboardContents(
        skinnyDipMarkdown: "# From Skinny Dip",
        html: "<h1>From HTML</h1>",
        plainText: "plain"
    )
    #expect(PasteAsMarkdown.insertText(from: contents) == "# From Skinny Dip")
}

@Test func pasteConvertsHTMLWhenNoSkinnyFlavor() {
    let contents = PasteboardContents(
        html: "<h2>Title</h2><p>Body</p>",
        plainText: "plain fallback"
    )
    #expect(PasteAsMarkdown.insertText(from: contents) == "## Title\n\nBody")
}

@Test func pasteFallsBackToPlainText() {
    let contents = PasteboardContents(plainText: "hello")
    #expect(PasteAsMarkdown.insertText(from: contents) == "hello")
}

@Test func pasteAndMatchStyleUsesPlainOnly() {
    let contents = PasteboardContents(
        skinnyDipMarkdown: "# ignored",
        html: "<h1>ignored</h1>",
        plainText: "plain only"
    )
    #expect(PasteAsMarkdown.plainInsertText(from: contents) == "plain only")
}

@Test func emptySkinnyFlavorFallsThroughToHTML() {
    let contents = PasteboardContents(
        skinnyDipMarkdown: "",
        html: "<p>from html</p>",
        plainText: "plain"
    )
    #expect(PasteAsMarkdown.insertText(from: contents) == "from html")
}
