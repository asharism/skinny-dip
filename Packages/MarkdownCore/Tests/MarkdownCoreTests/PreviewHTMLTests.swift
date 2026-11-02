import Foundation
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
    #expect(strippingPreviewAttributes(PreviewHTML.render(source)) == strippingPreviewAttributes(BareHTML.render(source)))
}

@Test func testSourceLineAnchors() {
    let lines = [
        "# Heading",
        "",
        "Paragraph",
        "continues",
        "",
        "- parent",
        "  - nested",
        "",
        "",
        "```",
        "code",
        "```",
        "",
        "",
        "| a | b |",
        "| --- | --- |",
        "| c | d |",
        "",
        "",
        "> quoted",
    ]
    let source = lines.joined(separator: "\n")
    let preview = PreviewHTML.render(source, options: .plain)
    #expect(preview.contains("<h1 data-source-line=\"1\">"))
    #expect(preview.contains("<p data-source-line=\"3\">"))
    #expect(preview.contains("<ul data-source-line=\"6\">"))
    #expect(preview.contains("<pre data-source-line=\"10\">"))
    #expect(preview.contains("<table data-source-line=\"15\">"))
    #expect(preview.contains("<blockquote data-source-line=\"20\">"))
    let lists = preview.matches(of: /<ul\b[^>]*>/).map { String($0.output) }
    #expect(lists.count == 2)
    #expect(lists.filter { $0.contains("data-source-line") }.count == 1)

    let demoted = PreviewHTML.render(source, options: RenderOptions(demotesHeadings: true, bordersTables: false, newlinesAsBreaks: true))
    #expect(demoted.contains("<h2 data-source-line=\"1\">"))
    #expect(demoted.contains("<p data-source-line=\"3\">"))
    #expect(demoted.contains("<br>"))

    let raw = PreviewHTML.render("<div>raw</div>\n", options: .plain)
    #expect(raw.contains("<p data-source-line=\"1\">"))
}

@Test func testBareHTMLHasNoSourceLines() throws {
    let root = Bundle.module.resourceURL!.appending(path: "Golden")
    let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    var sawMarkdown = false
    for folder in folders where folder.hasDirectoryPath {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "md" {
            sawMarkdown = true
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!BareHTML.render(source).contains("data-source-line"))
            #expect(!BareHTML.render(source, options: .plain).contains("data-source-line"))
        }
    }
    #expect(sawMarkdown)
}

private func strippingPreviewAttributes(_ html: String) -> String {
    html
        .replacingOccurrences(of: #" data-lang="[^"]*""#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #" data-source-line="\d+""#, with: "", options: .regularExpression)
}
